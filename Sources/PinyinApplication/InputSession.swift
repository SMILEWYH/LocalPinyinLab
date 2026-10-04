import Foundation
import PinyinCore

/// Owns one host's composition and async work, serialized on the main actor.
/// Query/page tickets are invalidated before state changes, even if providers ignore cancellation.
@MainActor public final class InputSession {
    public var mode: InputMode { modeState.mode }
    private let modeState: InputModeState
    public private(set) var composition = CompositionState()
    public private(set) var candidates = CandidateList()
    private let provider: any CandidateProviding
    private let translator: any CandidateTranslating
    private let speaker: any SpeechPlaying
    private let presenter: any CandidatePresenting
    private var host: (any InputHost)?
    private var documentContext = ""
    private var queryID: UUID?
    private var translationID: UUID?
    private var queryTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private var queuedSelection: Int?
    private var speechStatus: String?

    public init(provider: any CandidateProviding, translator: any CandidateTranslating,
                speaker: any SpeechPlaying, presenter: any CandidatePresenting,
                modeState: InputModeState = InputModeState()) {
        self.provider = provider
        self.translator = translator
        self.speaker = speaker
        self.presenter = presenter
        self.modeState = modeState
    }

    deinit { queryTask?.cancel(); translationTask?.cancel() }

    public func activate(capsLock: Bool? = nil) {
        if let capsLock { modeState.synchronizeCapsLock(capsLock) }
        provider.warm()
    }

    /// The OS can deliver the same modifier state more than once, including on
    /// the next keyDown. Only the edge changes mode, before any host callback.
    @discardableResult public func handleCapsLock(_ enabled: Bool, host nextHost: any InputHost) -> Bool {
        guard bind(nextHost) else { return false }
        return observeCapsLock(enabled)
    }

    private func observeCapsLock(_ enabled: Bool) -> Bool {
        guard modeState.observeCapsLock(enabled) else { return false }
        finishComposition()
        return true
    }

    public func synchronizeCapsLock(_ enabled: Bool) { modeState.synchronizeCapsLock(enabled) }

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
        host = nextHost
        return true
    }

    @discardableResult public func handle(_ key: KeyStroke, host nextHost: any InputHost) -> Bool {
        guard bind(nextHost) else { return false }
        _ = observeCapsLock(key.capsLock)
        guard host === nextHost else { return false }
        if mode == .chinesePinyin, !composition.isEmpty, key.requestsSpeech {
            if !key.isRepeat { speakHighlighted() }
            return true
        }
        if key.switchesMode {
            if !key.isRepeat {
                modeState.toggle()
                finishComposition()
            }
            return true
        }
        guard !key.passesThrough else { return false }
        let text = key.textIgnoringCapsLock
        if mode == .englishDirect { return forwardCorrectedText(text, original: key.characters, to: nextHost) }
        if key.code == 53 && !composition.isEmpty { cancel(); return true }
        if key.code == 51 && !composition.isEmpty { composition.backspace(); refresh(); return true }
        if key.code == 123 && composition.undoSelection() { refresh(); return true }
        if (key.code == 36 || key.code == 76) && !composition.isEmpty { commit(); return true }
        if key.code == 49 && !composition.isEmpty { select(offset: candidates.highlighted); return true }
        if !composition.isEmpty, let digit = Int(key.characters), (1...PinyinRules.pageSize).contains(digit) {
            select(offset: digit - 1)
            return true
        }
        if !composition.isEmpty && (key.code == 121 || key.code == 116) {
            stopSpeech()
            candidates.movePage(by: key.code == 121 ? 1 : -1)
            show()
            translateVisiblePage()
            return true
        }
        if !composition.isEmpty && (key.code == 125 || key.code == 126) && !candidates.rows.isEmpty {
            stopSpeech()
            candidates.move(by: key.code == 125 ? 1 : -1)
            show()
            translateVisiblePage()
            return true
        }
        if !text.isEmpty && text.unicodeScalars.allSatisfy({ (97...122).contains($0.value) || $0.value == 39 }) {
            let beginning = composition.isEmpty
            guard composition.append(text) else { return true }
            if beginning { documentContext = PinyinRules.boundedContext(nextHost.precedingContext()) }
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
        let previousHost = host
        let text = composition.isEmpty ? nil : composition.markedText
        clear()
        host = nil
        if let text { previousHost?.commit(text) }
    }

    /// Secure-input transitions discard composition and clear the host's marked text.
    public func cancel() {
        let previousHost = host
        clear()
        previousHost?.setMarkedText("")
    }

    private func select(offset: Int) {
        guard let index = candidates.indexOnPage(offset) else {
            if queryID != nil { queuedSelection = offset }
            return
        }
        guard composition.choose(candidates.rows[index].candidate) else { return }
        if composition.pending.isEmpty { commit() } else { refresh() }
    }

    private func refresh() {
        invalidateRequests()
        stopSpeech()
        candidates.clear()
        host?.setMarkedText(composition.markedText)
        guard !composition.pending.isEmpty else { presenter.hide(); return }
        presenter.showLoading(pinyin: composition.markedText)
        let query = composition.pending
        let context = PinyinRules.boundedContext(documentContext + composition.selectedText)
        let ticket = UUID()
        queryID = ticket
        let provider = provider
        queryTask = Task { [weak self] in
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
        translationTask?.cancel()
        translationTask = nil
        translationID = nil
        let indices = candidates.visibleIndices.filter {
            candidates.rows[$0].needsTranslation && candidates.rows[$0].speechText == nil
        }
        guard !indices.isEmpty else { return }
        let sources = indices.map { candidates.rows[$0].text }
        let ticket = UUID()
        translationID = ticket
        let translator = translator
        translationTask = Task { [weak self] in
            let states: [TranslationState]
            do {
                let text = try await translator.translate(sources)
                guard text.count == sources.count, text.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                    throw TranslationFailure.invalidResponse
                }
                states = text.map { .ready($0) }
            } catch TranslationFailure.modelsNotInstalled {
                states = sources.map { _ in .unavailable(.modelsNotInstalled) }
            } catch {
                states = sources.map { _ in .unavailable(.failed) }
            }
            guard let self, self.translationID == ticket, !Task.isCancelled else { return }
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
        guard !candidates.rows.isEmpty else { presenter.hide(); return }
        presenter.show(CandidatePresentation(candidates: candidates, markedText: composition.markedText, status: speechStatus))
    }

    private func speakHighlighted() {
        stopSpeech()
        if let text = candidates.selectedRow?.speechText {
            if !speaker.speak(text) { speechStatus = "未找到本地英语声音" }
        } else { speechStatus = "当前项尚无可朗读译文" }
        show()
    }

    private func stopSpeech() { speaker.stop(); speechStatus = nil }

    private func commit() {
        guard !composition.isEmpty else { return }
        let text = composition.markedText
        let previousHost = host
        // Invalidate before calling the host, which may synchronously trigger lifecycle callbacks.
        clear()
        previousHost?.commit(text)
    }

    private func invalidateRequests() {
        queryID = nil
        translationID = nil
        queryTask?.cancel(); queryTask = nil
        translationTask?.cancel(); translationTask = nil
        queuedSelection = nil
    }

    private func clear() {
        invalidateRequests()
        stopSpeech()
        composition = CompositionState()
        documentContext = ""
        candidates.clear()
        presenter.hide()
    }
}
