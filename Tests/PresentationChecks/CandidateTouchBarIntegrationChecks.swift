import AppKit
import PinyinCore
import PinyinApplication
import PinyinPresentation

extension PresentationChecks {
    /// Fake windows and a recording sink exercise integration without changing
    /// the real Touch Bar, input source, foreground application, or keyboard focus.
    @MainActor static func checkCandidateTouchBarIntegration() async throws {
        touchBarTracksCurrentPresentation()
        touchBarClearsNonCandidatePresentations()
        try await touchBarKeepsControllerOwnership()
        try await touchBarClearsWhenPresenterIsReleased()
        try await touchBarClearsThroughSessionLifecycle()
    }

    @MainActor private static func touchBarTracksCurrentPresentation() {
        let sink = RecordingCandidateTouchBar()
        let presenter = touchBarPanel(sink)
        defer { presenter.hide() }
        var candidates = CandidateList(rows: (0..<11).map { index in
            CandidateRow(candidate: Candidate(text: "候选\(index + 1)", consumedCount: 2))
        })
        presenter.show(CandidatePresentation(candidates: candidates, markedText: "ni"))
        let owner = sink.current!.owner
        precondition(sink.current?.row == candidates.rows[0] && sink.current?.language == .english,
                     "the Touch Bar must receive the selected candidate and its pending translation")

        candidates.move(by: 2)
        presenter.show(CandidatePresentation(candidates: candidates, markedText: "ni"))
        precondition(sink.current?.row == candidates.rows[2] && sink.current?.owner == owner,
                     "highlight updates must replace the Touch Bar row without changing ownership")
        candidates.updateTranslation(at: 2, source: "候选3", state: .ready("Candidate three"))
        presenter.show(CandidatePresentation(candidates: candidates, markedText: "ni"))
        precondition(sink.current?.row.translation == .ready("Candidate three"),
                     "late translation updates must reach the already selected Touch Bar row")

        candidates.resetTranslations()
        presenter.show(CandidatePresentation(candidates: candidates, markedText: "ni", translationLanguage: .japanese))
        precondition(sink.current?.row.translation == .pending && sink.current?.language == .japanese,
                     "language changes must discard the previous translation and pass the new language")
        candidates.updateTranslation(at: 2, source: "候选3", state: .unavailable(.modelsNotInstalled))
        presenter.show(CandidatePresentation(candidates: candidates, markedText: "ni", translationLanguage: .japanese))
        precondition(sink.current?.row.translationText(for: .japanese).contains("日语") == true,
                     "language-aware translation errors must remain available to the Touch Bar")

        candidates.movePage(by: 1)
        presenter.show(CandidatePresentation(candidates: candidates, markedText: "ni", translationLanguage: .japanese))
        precondition(sink.current?.row == candidates.rows[9] && sink.current?.owner == owner,
                     "paging must use the new page's highlighted row rather than the first global candidate")
        precondition(sink.shown.count == 6, "every presentation change must publish exactly one selected row")
        precondition(presenter.panel.frame.width <= 600 && !presenter.panel.isKeyWindow && !presenter.panel.isMainWindow,
                     "Touch Bar integration must preserve the 600-point cap and nonactivating candidate panel")
    }

    @MainActor private static func touchBarClearsNonCandidatePresentations() {
        let sink = RecordingCandidateTouchBar()
        let presenter = touchBarPanel(sink)
        defer { presenter.hide() }
        let row = CandidateRow(candidate: Candidate(text: "你好", consumedCount: 2), translation: .ready("Hello"))
        let actions: [(String, (CandidatePanel) -> Void)] = [
            ("loading", { $0.showLoading(pinyin: "nihao") }),
            ("mode status", { $0.showModeStatus(mode: .englishDirect) }),
            ("case status", { $0.showCaseStatus(uppercaseLocked: true) }),
            ("hidden candidates", { $0.hide() }),
            ("empty candidates", { showTouchBarRows([], selected: 0, on: $0) }),
            ("negative selection", { showTouchBarRows([row], selected: -1, on: $0) }),
            ("out-of-range selection", { showTouchBarRows([row], selected: 1, on: $0) })
        ]
        for (name, clear) in actions {
            showTouchBarRows([row], selected: 0, on: presenter)
            let owner = sink.current!.owner
            let hidden = sink.hidden.count
            clear(presenter)
            precondition(sink.current == nil && sink.hidden.count == hidden + 1 && sink.hidden.last == owner,
                         "\(name) must clear only this presenter's Touch Bar content")
        }
    }

    @MainActor private static func touchBarKeepsControllerOwnership() async throws {
        let sink = RecordingCandidateTouchBar()
        let first = touchBarPanel(sink)
        let second = touchBarPanel(sink)
        defer { first.hide(); second.hide() }
        let firstRow = CandidateRow(candidate: Candidate(text: "旧候选", consumedCount: 2), translation: .ready("Old"))
        let secondRow = CandidateRow(candidate: Candidate(text: "新候选", consumedCount: 2), translation: .ready("New"))
        showTouchBarRows([firstRow], selected: 0, on: first)
        let firstOwner = sink.current!.owner
        showTouchBarRows([secondRow], selected: 0, on: second)
        let secondOwner = sink.current!.owner
        precondition(firstOwner != secondOwner, "each input controller must receive an independent Touch Bar owner")
        first.hide()
        precondition(sink.hidden.last == firstOwner && sink.current?.owner == secondOwner && sink.current?.row == secondRow,
                     "an old controller hiding must not clear the current controller's Touch Bar")

        first.showModeStatus(mode: .chinesePinyin)
        let hiddenBeforeTimer = sink.hidden.count
        try await waitForTouchBar { sink.hidden.count > hiddenBeforeTimer }
        precondition(sink.hidden.last == firstOwner && sink.current?.owner == secondOwner && sink.current?.row == secondRow,
                     "an old controller's status expiry must not clear a newer controller's Touch Bar")
    }

    @MainActor private static func touchBarClearsWhenPresenterIsReleased() async throws {
        let sink = RecordingCandidateTouchBar()
        var presenter: CandidatePanel? = touchBarPanel(sink)
        weak let released = presenter
        let owner = withExtendedLifetime(presenter) {
            showTouchBarRows([CandidateRow(candidate: Candidate(text: "你好", consumedCount: 2))], selected: 0, on: presenter!)
            guard let current = sink.current else { preconditionFailure("the live presenter must publish its Touch Bar row") }
            return current.owner
        }
        presenter = nil
        try await waitForTouchBar { released == nil && sink.hidden.last == owner }
        precondition(sink.current == nil, "releasing the presenter must dismiss its Touch Bar content")
    }

    @MainActor private static func touchBarClearsThroughSessionLifecycle() async throws {
        for cancel in [false, true] {
            let sink = RecordingCandidateTouchBar()
            let presenter = touchBarPanel(sink)
            let host = TouchBarInputHost()
            let session = InputSession(provider: TouchBarCandidateProvider(), translator: TouchBarTranslator(),
                                       speaker: TouchBarSpeaker(), presenter: presenter)
            precondition(session.handle(KeyStroke(code: 45, characters: "ni", modifiers: [], capsLock: false), host: host),
                         "the fixture must start a real input session")
            try await waitForTouchBar { sink.current?.row.translation == .ready("Hello") }
            let owner = sink.current!.owner
            if cancel { session.cancel() } else { session.deactivate() }
            precondition(sink.current == nil && sink.hidden.last == owner && !presenter.panel.isVisible,
                         "deactivation and secure-input cancellation must dismiss both candidate presentations")
        }
    }

    @MainActor private static func touchBarPanel(_ sink: RecordingCandidateTouchBar) -> CandidatePanel {
        CandidatePanel(touchBar: sink, diagnosticOwner: "touch-bar-test", panelFactory: { TouchBarOffscreenPanel() },
                       foregroundPID: { nil })
    }

    @MainActor private static func showTouchBarRows(_ rows: [CandidateRow], selected: Int, on presenter: CandidatePanel) {
        presenter.show(rows: rows, pinyin: "ni", selected: selected, page: 0, totalPages: 1,
                       anchor: NSRect(x: 300, y: 400, width: 1, height: 20))
    }

    @MainActor private static func waitForTouchBar(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        precondition(predicate(), "Touch Bar integration did not reach the expected state")
    }
}

@MainActor private final class RecordingCandidateTouchBar: CandidateTouchBarDisplaying {
    struct Presentation {
        let owner: UUID
        let row: CandidateRow
        let language: TranslationLanguage
    }
    private(set) var current: Presentation?
    private(set) var shown: [Presentation] = []
    private(set) var hidden: [UUID] = []

    func show(owner: UUID, row: CandidateRow, language: TranslationLanguage) {
        let presentation = Presentation(owner: owner, row: row, language: language)
        current = presentation
        shown.append(presentation)
    }

    func hide(owner: UUID) {
        hidden.append(owner)
        if current?.owner == owner { current = nil }
    }
}

@MainActor private final class TouchBarOffscreenPanel: NSPanel {
    private var simulatedVisible = false
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    }
    override var isVisible: Bool { simulatedVisible }
    override func orderFrontRegardless() { simulatedVisible = true }
    override func orderOut(_ sender: Any?) { simulatedVisible = false }
}

@MainActor private final class TouchBarCandidateProvider: CandidateProviding {
    func warm() {}
    func candidates(for pinyin: String, context: String) async throws -> [Candidate] {
        [Candidate(text: "你好", consumedCount: pinyin.count)]
    }
}

@MainActor private final class TouchBarTranslator: CandidateTranslating {
    func translate(_ sources: [String], to language: TranslationLanguage) async throws -> [String] {
        sources.map { _ in "Hello" }
    }
}

@MainActor private final class TouchBarSpeaker: SpeechPlaying {
    func speak(_ text: String, language: TranslationLanguage) -> Bool { true }
    func stop() {}
}

@MainActor private final class TouchBarInputHost: InputHost {
    func precedingContext() -> String { "" }
    func setMarkedText(_ text: String) {}
    func commit(_ text: String) {}
}
