import Foundation
import PinyinCore

/// Owns one host's composition and async work, serialized on the main actor.
/// Query/page tickets are invalidated before state changes, even if providers ignore cancellation.
@MainActor public final class InputSession {
    public enum QueryState: Sendable, Equatable {
        case idle
        case querying
        case ready
        case selectedTextOnly
    }

    public var mode: InputMode { modeState.mode }
    public var isUppercaseLocked: Bool { modeState.isUppercaseLocked }
    private let modeState: InputModeState
    public private(set) var composition = CompositionState()
    public private(set) var candidates = CandidateList()
    public private(set) var queryState: QueryState = .idle
    public private(set) var translationLanguage: TranslationLanguage
    public private(set) var speechShortcut: SpeechShortcut
    private let provider: any CandidateProviding
    private let translator: any CandidateTranslating
    private let speaker: any SpeechPlaying
    private let presenter: any CandidatePresenting
    private var host: (any InputHost)?
    private var hostRevision: UInt64 = 0
    private var compositionRevision: UInt64 = 0
    private struct CallbackRevision: Equatable {
        let host: UInt64
        let composition: UInt64
        let mode: UInt64
    }
    private var callbackRevision: CallbackRevision {
        CallbackRevision(host: hostRevision, composition: compositionRevision, mode: modeState.revision)
    }
    private var documentContext = ""
    private var contextReadID: UUID?
    private var queryID: UUID?
    private var translationID: UUID?
    private var queryTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private struct TranslationPage: Equatable {
        let language: TranslationLanguage
        let indices: [Int]
        let sources: [String]
    }
    private var translationPage: TranslationPage?
    private var queuedSelection: Int?
    private var speechStatus: String?
    private enum SpeechGesture { case idle, collecting, armed, releasing, blocked }
    private var speechGesture: SpeechGesture = .idle
    private var speechModifiers: KeyModifiers = []

    public init(provider: any CandidateProviding, translator: any CandidateTranslating,
                speaker: any SpeechPlaying, presenter: any CandidatePresenting,
                modeState: InputModeState = InputModeState(), translationLanguage: TranslationLanguage = .english,
                speechShortcut: SpeechShortcut = .default) {
        self.provider = provider
        self.translator = translator
        self.speaker = speaker
        self.presenter = presenter
        self.modeState = modeState
        self.translationLanguage = translationLanguage
        self.speechShortcut = speechShortcut
    }

    deinit { queryTask?.cancel(); translationTask?.cancel() }

    public func activate(capsLock: Bool? = nil) {
        speechGesture = .blocked
        if let capsLock { modeState.synchronizeCapsLock(capsLock) }
        provider.warm()
    }

    public func setSpeechShortcut(_ shortcut: SpeechShortcut) {
        guard speechShortcut != shortcut else { return }
        speechShortcut = shortcut
        stopSpeech()
    }

    /// A cancelled chord cannot restart while any of its modifiers remain held.
    /// Adapters also call this for mouse events, focus changes and missed keyDowns.
    public func cancelSpeechShortcutGesture() {
        // External cancellation may precede our first flagsChanged event, so
        // the last observed modifiers cannot establish a clean keyboard state.
        speechGesture = .blocked
    }

    public var isSpeechShortcutGestureInProgress: Bool {
        switch speechGesture {
        case .collecting, .armed, .releasing: return true
        case .idle, .blocked: return false
        }
    }

    private var canSpeakHighlighted: Bool {
        mode == .chinesePinyin && !composition.isEmpty && queryState == .ready && candidates.selectedRow?.speechText != nil
    }

    /// Modifier-only chords speak after every modifier has been released. A
    /// release/repress, an extra modifier or another key invalidates the chord.
    @discardableResult public func handleSpeechModifiers(_ modifiers: KeyModifiers, host nextHost: any InputHost) -> Bool {
        guard bind(nextHost) else { return false }
        let previous = speechModifiers
        speechModifiers = modifiers
        guard speechShortcut.isModifierOnly else { speechGesture = .idle; return false }
        if modifiers.isEmpty {
            let completed = speechGesture == .armed || speechGesture == .releasing
            speechGesture = .idle
            guard completed, canSpeakHighlighted else { return false }
            speakHighlighted()
            return true
        }
        let expected = speechShortcut.modifiers
        guard modifiers.isSubset(of: expected), canSpeakHighlighted else { speechGesture = .blocked; return false }
        switch speechGesture {
        case .idle:
            guard previous.isEmpty else { speechGesture = .blocked; return false }
            speechGesture = modifiers == expected ? .armed : .collecting
        case .collecting:
            guard previous.isSubset(of: modifiers) else { speechGesture = .blocked; return false }
            if modifiers == expected { speechGesture = .armed }
        case .armed:
            if modifiers != expected { speechGesture = .releasing }
        case .releasing:
            if !modifiers.isSubset(of: previous) { speechGesture = .blocked }
        case .blocked: break
        }
        return false
    }

    /// Retarget translations without losing the current composition or page.
    /// Query tickets stay valid; a query still loading uses the new target.
    public func setTranslationLanguage(_ language: TranslationLanguage) {
        guard translationLanguage != language else { return }
        translationLanguage = language
        invalidateTranslationRequest()
        stopSpeech()
        candidates.resetTranslations()
        if queryState == .ready {
            show()
            translateVisiblePage()
        }
    }

    /// The OS can deliver the same modifier state more than once, including on
    /// the next keyDown. Only the edge changes mode, before any host callback.
    @discardableResult public func handleCapsLock(_ enabled: Bool, modifiers: KeyModifiers = [], host nextHost: any InputHost) -> Bool {
        guard bind(nextHost) else { return false }
        return observeCapsLock(enabled, modifiers: modifiers, isCapsLockEvent: true)
    }

    private func observeCapsLock(_ enabled: Bool, modifiers: KeyModifiers, isCapsLockEvent: Bool) -> Bool {
        guard modeState.observeCapsLock(enabled, modifiers: modifiers, allowsUppercaseToggle: isCapsLockEvent) else { return false }
        finishModeChange(showCase: isCapsLockEvent && modifiers == [.shift])
        return true
    }

    private func finishModeChange(showCase: Bool) {
        let expectedHost = host
        let expectedHostRevision = hostRevision
        let expectedModeRevision = modeState.revision
        finishComposition()
        // A commit can synchronously switch clients or process another mode
        // change. Only the still-current transition may present its status.
        if let expectedHost,
           host === expectedHost, hostRevision == expectedHostRevision,
           modeState.revision == expectedModeRevision {
            if showCase { presenter.showCaseStatus(uppercaseLocked: isUppercaseLocked) }
            else { presenter.showModeStatus(mode: mode) }
        }
    }

    public func synchronizeCapsLock(_ enabled: Bool) { modeState.synchronizeCapsLock(enabled) }
    public func acknowledgeCapsLock(_ enabled: Bool) { modeState.acknowledgeCapsLock(enabled) }

    /// Used for mouse clicks as well as mode changes. Does not discard the host.
    public func finishComposition() {
        if composition.isEmpty { clear() } else { commit() }
    }

    private func bind(_ nextHost: any InputHost) -> Bool {
        if let host, host !== nextHost {
            deactivate()
            // Submission may synchronously activate another client and start a
            // new composition. Do not move that text into this obsolete client.
            guard self.host == nil else { return false }
        }
        if host !== nextHost { hostRevision &+= 1 }
        host = nextHost
        return true
    }

    @discardableResult public func handle(_ key: KeyStroke, host nextHost: any InputHost) -> Bool {
        speechModifiers = key.modifiers
        speechGesture = key.modifiers.isEmpty ? .idle : .blocked
        guard bind(nextHost) else { return false }
        _ = observeCapsLock(key.capsLock, modifiers: key.modifiers, isCapsLockEvent: false)
        guard host === nextHost else { return false }
        if speechShortcut.keyCode == key.code, speechShortcut.modifiers == key.modifiers, canSpeakHighlighted {
            if !key.isRepeat { speakHighlighted() }
            return true
        }
        guard !key.passesThrough else { return false }
        let text = key.text(uppercaseLocked: isUppercaseLocked)
        if mode == .englishDirect { return forwardCorrectedText(text, original: key.characters, to: nextHost) }
        if key.code == 53 && !composition.isEmpty { cancel(); return true }
        if key.code == 51 && !composition.isEmpty { composition.backspace(); refresh(); return true }
        if key.code == 123 && key.modifiers == [.shift] && !composition.isEmpty {
            if composition.undoSelection() { refresh() }
            return true
        }
        if (key.code == 36 || key.code == 76) && !composition.isEmpty { commit(); return true }
        if key.code == 49 && !composition.isEmpty {
            if queryState == .selectedTextOnly { commit() }
            else { select(offset: candidates.highlighted) }
            return true
        }
        if !composition.isEmpty, let digit = Int(key.characters), (1...PinyinRules.pageSize).contains(digit) {
            select(offset: digit - 1)
            return true
        }
        let arrowPages = key.modifiers.isEmpty && (key.code == 123 || key.code == 124)
        if !composition.isEmpty && (arrowPages || key.code == 121 || key.code == 116) {
            // Navigation supersedes a selection queued while candidates load.
            queuedSelection = nil
            stopSpeech()
            if queryState == .ready, key.modifiers == [.shift],
               presenter.scrollHighlightedCandidate(by: key.code == 121 ? 1 : -1) {
                return true
            }
            candidates.movePage(by: key.code == 121 || key.code == 124 ? 1 : -1)
            show()
            translateVisiblePage()
            return true
        }
        if !composition.isEmpty && (key.code == 125 || key.code == 126) {
            // Loading and selected-text-only states still own navigation keys.
            queuedSelection = nil
            stopSpeech()
            candidates.move(by: key.code == 125 ? 1 : -1)
            show()
            translateVisiblePage()
            return true
        }
        // An apostrophe inside raw pinyin separates syllables (xi'an).
        // Elsewhere it is a quotation mark, just like the double-quote key.
        if text != "'" || composition.pending.isEmpty {
            let isQuote = text == "'" || text == "\""
            let context = isQuote ? PinyinRules.boundedContext(nextHost.precedingContext()) : ""
            guard host === nextHost, mode == .chinesePinyin else { return false }
            if let punctuation = ChinesePunctuation.text(for: text, preceding: context) {
                commit(suffix: punctuation)
                return true
            }
        }
        if !text.isEmpty && text.unicodeScalars.allSatisfy({ (97...122).contains($0.value) || $0.value == 39 }) {
            let beginning = composition.isEmpty
            guard composition.append(text) else { return true }
            if beginning {
                let revision = callbackRevision
                let contextTicket = UUID()
                contextReadID = contextTicket
                let context = PinyinRules.boundedContext(nextHost.precedingContext())
                // A new host/composition owns its own read. Edits of this same
                // composition wait for this read instead of querying with empty context.
                guard contextReadID == contextTicket else { return true }
                contextReadID = nil
                guard hostRevision == revision.host, modeState.revision == revision.mode else { return true }
                documentContext = context
                if compositionRevision != revision.composition {
                    startQuery()
                    return true
                }
                refresh(preservingSelection: queuedSelection)
                return true
            }
            refresh()
            return true
        }
        commit()
        guard host === nextHost else { return false }
        return forwardCorrectedText(text, original: key.characters, to: nextHost)
    }

    private func forwardCorrectedText(_ text: String, original: String, to host: any InputHost) -> Bool {
        guard text != original else { return false }
        host.commit(text)
        return true
    }

    public func deactivate() {
        cancelSpeechShortcutGesture()
        hostRevision &+= 1
        let previousHost = host
        let text = composition.isEmpty ? nil : composition.markedText
        let segments = composition.segments
        clear()
        host = nil
        if let text, let previousHost {
            if !segments.isEmpty { provider.recordCommittedSegments(segments) }
            previousHost.commit(text)
        }
    }

    /// Secure-input transitions discard composition and clear the host's marked text.
    public func cancel() {
        cancelSpeechShortcutGesture()
        hostRevision &+= 1
        let previousHost = host
        clear()
        previousHost?.setMarkedText("")
    }

    private func select(offset: Int) {
        if queryState == .querying || contextReadID != nil { queuedSelection = offset; return }
        guard queryState == .ready else { return }
        guard let index = candidates.indexOnPage(offset) else {
            return
        }
        guard composition.choose(candidates.rows[index].candidate) else { return }
        if composition.pending.isEmpty { commit() } else { refresh() }
    }

    private func refresh(preservingSelection selection: Int? = nil) {
        invalidateRequests()
        queuedSelection = selection
        stopSpeech()
        candidates.clear()
        queryState = composition.isEmpty ? .idle : composition.pending.isEmpty ? .selectedTextOnly : .querying
        let revision = callbackRevision
        host?.setMarkedText(composition.markedText)
        guard callbackRevision == revision else { return }
        guard queryState == .querying else { show(); return }
        presenter.showLoading(pinyin: composition.markedText)
        guard callbackRevision == revision else { return }
        startQuery()
    }

    private func startQuery() {
        guard queryState == .querying, contextReadID == nil, queryID == nil else { return }
        let query = composition.pending
        let context = PinyinRules.boundedContext(documentContext + composition.selectedText)
        let ticket = UUID()
        queryID = ticket
        let provider = provider
        queryTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            do {
                let result = try await provider.candidates(for: query, context: context)
                guard let self, self.queryID == ticket, !Task.isCancelled else { return }
                self.finishQuery(result, query: query, issue: .noCandidates)
            } catch {
                guard let self, self.queryID == ticket, !Task.isCancelled else { return }
                self.finishQuery([], query: query, issue: .engineUnavailable)
            }
        }
    }

    private func finishQuery(_ result: [Candidate], query: String, issue: TranslationIssue) {
        queryID = nil
        queryTask = nil
        // Providers are replaceable; invalid candidates must never consume or discard input.
        let valid = result.filter {
            CandidateTextPolicy.allows($0.text) &&
                $0.consumedCount > 0 && $0.consumedCount <= query.count
        }
        let rows = valid.isEmpty
            ? [CandidateRow(candidate: Candidate(text: query, consumedCount: query.count), translation: .unavailable(issue))]
            : valid.map { CandidateRow(candidate: $0) }
        candidates.replace(rows)
        queryState = .ready
        let selection = queuedSelection
        queuedSelection = nil
        if let selection, candidates.indexOnPage(selection) != nil {
            select(offset: selection)
            return
        }
        // An early "9" with fewer than nine results must still show the returned candidates.
        show()
        translateVisiblePage()
    }

    private func translateVisiblePage() {
        guard queryState == .ready else { return }
        let language = translationLanguage
        let page = TranslationPage(language: language, indices: candidates.visibleIndices, sources: candidates.visibleRows.map(\.text))
        // Highlight changes and paging against a boundary retain the same batch,
        // including a completed failure. A different page or query may retry it.
        guard translationPage != page else { return }
        invalidateTranslationRequest()
        translationPage = page
        let indices = candidates.visibleIndices.filter {
            candidates.rows[$0].needsTranslation && candidates.rows[$0].speechText == nil
        }
        guard !indices.isEmpty else { return }
        let sources = indices.map { candidates.rows[$0].text }
        let ticket = UUID()
        translationID = ticket
        let translator = translator
        translationTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let states: [TranslationState]
            do {
                let text = try await translator.translate(sources, to: language)
                guard text.count == sources.count, text.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                    throw TranslationFailure.invalidResponse
                }
                states = text.map { .ready($0) }
            } catch TranslationFailure.modelsNotInstalled {
                states = sources.map { _ in .unavailable(.modelsNotInstalled) }
            } catch {
                states = sources.map { _ in .unavailable(.failed) }
            }
            guard let self, self.translationID == ticket, self.translationLanguage == language, !Task.isCancelled else { return }
            self.translationTask = nil
            self.translationID = nil
            let oldSpeech = self.candidates.selectedRow?.speechText
            for (offset, index) in indices.enumerated() {
                _ = self.candidates.updateTranslation(at: index, source: sources[offset], state: states[offset])
            }
            if oldSpeech != self.candidates.selectedRow?.speechText { self.stopSpeech() }
            self.speechStatus = nil
            self.show()
        }
    }

    private func show() {
        switch queryState {
        case .querying:
            presenter.showLoading(pinyin: composition.markedText)
        case .ready:
            presenter.show(CandidatePresentation(candidates: candidates, markedText: composition.markedText, status: speechStatus,
                                                 translationLanguage: translationLanguage))
        case .idle, .selectedTextOnly:
            presenter.hide()
        }
    }

    private func speakHighlighted() {
        stopSpeech()
        if let text = candidates.selectedRow?.speechText {
            if !speaker.speak(text, language: translationLanguage) { speechStatus = "未找到本地\(translationLanguage.displayName)声音" }
        } else { speechStatus = "当前项尚无可朗读译文" }
        show()
    }

    private func stopSpeech() {
        if isSpeechShortcutGestureInProgress { cancelSpeechShortcutGesture() }
        speaker.stop()
        speechStatus = nil
    }

    private func commit(suffix: String = "") {
        guard !composition.isEmpty || !suffix.isEmpty else { return }
        let text = composition.markedText + suffix
        let previousHost = host
        let segments = composition.segments
        // Invalidate before calling the host, which may synchronously trigger lifecycle callbacks.
        clear()
        if let previousHost {
            // Queue learning before a reentrant host can start the next query.
            if !segments.isEmpty { provider.recordCommittedSegments(segments) }
            previousHost.commit(text)
        }
    }

    private func invalidateRequests() {
        compositionRevision &+= 1
        queryID = nil
        queryState = .idle
        queryTask?.cancel(); queryTask = nil
        invalidateTranslationRequest()
        queuedSelection = nil
    }

    private func invalidateTranslationRequest() {
        translationID = nil
        translationPage = nil
        translationTask?.cancel()
        translationTask = nil
    }

    private func clear() {
        invalidateRequests()
        contextReadID = nil
        stopSpeech()
        composition = CompositionState()
        documentContext = ""
        candidates.clear()
        presenter.hide()
    }
}
