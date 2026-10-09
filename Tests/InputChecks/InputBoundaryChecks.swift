import Foundation
import PinyinApplication
import PinyinCore

@MainActor final class InputBoundaryChecks {
    func contextReentryWithinTheCompositionKeepsItsContext() async throws {
        for appendsInput in [false, true] {
            for selection: Int? in [nil, 0, 1] {
                let fixture = BoundaryFixture()
                fixture.host.onContext = {
                    if appendsInput { _ = fixture.press(34, "i") }
                    if let selection { _ = fixture.press(selection == 0 ? 49 : 19, selection == 0 ? " " : "2") }
                }
                try checkTrue(fixture.press(45, "n"))
                let pinyin = appendsInput ? "ni" : "n"
                if let selection {
                    let deadline = ContinuousClock.now + .seconds(2)
                    while fixture.host.committed.isEmpty, ContinuousClock.now < deadline {
                        try await Task.sleep(for: .milliseconds(1))
                    }
                    try checkEqual(fixture.host.committed, ["词\(selection + 1)"])
                } else {
                    try await fixture.waitForCandidates()
                    try checkEqual(fixture.session.composition.pending, pinyin)
                }
                try checkEqual(fixture.provider.queries.map(\.pinyin), [pinyin])
                try checkEqual(fixture.provider.queries.map(\.context), ["原文档"])
                fixture.session.cancel()
            }
        }
    }

    func contextReentryKeepsTheNewHostsContext() async throws {
        let fixture = BoundaryFixture()
        let nextHost = BoundaryHost(context: "新文档")
        fixture.host.onContext = {
            _ = fixture.session.handle(KeyStroke(code: 4, characters: "hao"), host: nextHost)
        }
        try checkTrue(fixture.press(45, "ni"))
        try await fixture.waitForCandidates()
        try checkEqual(fixture.provider.queries.map(\.pinyin), ["hao"])
        try checkEqual(fixture.provider.queries.map(\.context), ["新文档"])
        try checkEqual(fixture.session.composition.pending, "hao")
        try checkEqual(fixture.host.committed, ["ni"])
        try checkEqual(nextHost.markedText, "hao")
        fixture.session.cancel()
    }

    func markedTextReentryStartsOnlyTheCurrentQuery() async throws {
        let fixture = BoundaryFixture()
        fixture.host.onMarked = { _ = fixture.press(34, "i") }
        try checkTrue(fixture.press(45, "n"))
        try await fixture.waitForCandidates()
        try checkEqual(fixture.provider.queries.map(\.pinyin), ["ni"])
        try checkEqual(fixture.provider.queries.map(\.context), ["原文档"])
        try checkEqual(fixture.host.markedText, "ni")
        try checkEqual(fixture.presenter.loading, ["ni"])
        fixture.session.cancel()
    }

    func loadingReentryStartsOnlyTheCurrentQuery() async throws {
        let fixture = BoundaryFixture()
        fixture.presenter.onLoading = { _ = fixture.press(34, "i") }
        try checkTrue(fixture.press(45, "n"))
        try await fixture.waitForCandidates()
        try checkEqual(fixture.provider.queries.map(\.pinyin), ["ni"])
        try checkEqual(fixture.session.composition.pending, "ni")
        fixture.session.cancel()
    }

    func cancellationDuringHostCallbacksCannotRestartInput() async throws {
        for readsContext in [false, true] {
            let fixture = BoundaryFixture()
            let cancel = { fixture.session.cancel() }
            if readsContext { fixture.host.onContext = cancel }
            else { fixture.host.onMarked = cancel }
            try checkTrue(fixture.press(45, "ni"))
            // Let any accidentally scheduled query run before checking its effects.
            try await Task.sleep(for: .milliseconds(10))
            try checkTrue(fixture.provider.queries.isEmpty)
            try checkTrue(fixture.session.composition.isEmpty)
            try checkEqual(fixture.session.queryState, .idle)
            try checkEqual(fixture.host.markedText, "")
            try checkTrue(fixture.presenter.loading.isEmpty)
        }
    }

    func overflowingCandidateScrollPreservesSelectionAndTranslation() async throws {
        let fixture = BoundaryFixture()
        try checkTrue(fixture.press(45, "ni"))
        try await fixture.waitForCandidates()
        try checkTrue(fixture.press(125))
        let selection = fixture.session.candidates.selectedIndex
        let rows = fixture.session.candidates.rows
        let translations = fixture.translator.calls
        fixture.presenter.overflows = true
        try checkTrue(fixture.press(121, modifiers: .shift))
        try checkTrue(fixture.press(116, modifiers: .shift))
        try checkEqual(fixture.presenter.scrolls, [1, -1])
        try checkEqual(fixture.session.candidates.selectedIndex, selection)
        try checkEqual(fixture.session.candidates.rows, rows)
        try checkEqual(fixture.translator.calls, translations)
        try checkEqual(fixture.session.composition.pending, "ni")
        try checkTrue(fixture.host.committed.isEmpty)
        // Unmodified page keys must retain candidate paging even for a tall row.
        try checkTrue(fixture.press(121))
        try checkEqual(fixture.session.candidates.page, 1)
        try checkEqual(fixture.presenter.scrolls, [1, -1])
        fixture.session.cancel()
    }

    func overflowShortcutFallsBackToPagingWhenTextFits() async throws {
        let fixture = BoundaryFixture()
        try checkTrue(fixture.press(45, "ni"))
        try await fixture.waitForCandidates()
        try checkTrue(fixture.press(121, modifiers: .shift))
        try checkEqual(fixture.session.candidates.page, 1)
        try checkTrue(fixture.press(116, modifiers: .shift))
        try checkEqual(fixture.session.candidates.page, 0)
        try checkFalse(fixture.press(121, modifiers: [.command, .shift]))
        try checkEqual(fixture.presenter.scrolls, [1, -1])
        fixture.session.cancel()
        try checkFalse(fixture.press(121, modifiers: .shift))
        try checkEqual(fixture.presenter.scrolls, [1, -1])
    }
}

@MainActor private final class BoundaryFixture {
    let provider = BoundaryProvider()
    let translator = BoundaryTranslator()
    let presenter = BoundaryPresenter()
    let host = BoundaryHost(context: "原文档")
    let session: InputSession

    init() {
        session = InputSession(provider: provider, translator: translator, speaker: BoundarySpeaker(), presenter: presenter)
        session.activate(capsLock: false)
    }
    func press(_ code: UInt16, _ text: String = "", modifiers: KeyModifiers = []) -> Bool {
        session.handle(KeyStroke(code: code, characters: text, modifiers: modifiers), host: host)
    }
    func waitForCandidates() async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while session.candidates.selectedRow?.speechText == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try checkTrue(session.candidates.selectedRow?.speechText != nil)
    }
}

@MainActor private final class BoundaryProvider: CandidateProviding {
    struct Query { let pinyin: String; let context: String }
    var queries: [Query] = []
    func warm() {}
    func candidates(for pinyin: String, context: String) async throws -> [Candidate] {
        queries.append(Query(pinyin: pinyin, context: context))
        return (1...20).map { Candidate(text: "词\($0)", consumedCount: pinyin.count) }
    }
}

@MainActor private final class BoundaryTranslator: CandidateTranslating {
    var calls = 0
    func translate(_ sources: [String], to language: TranslationLanguage) async throws -> [String] {
        calls += 1
        return sources.map { "translated " + $0 }
    }
}

@MainActor private final class BoundarySpeaker: SpeechPlaying {
    func speak(_ text: String, language: TranslationLanguage) -> Bool { true }
    func stop() {}
}

@MainActor private final class BoundaryPresenter: CandidatePresenting {
    var loading: [String] = []
    var onLoading: (() -> Void)?
    var overflows = false
    var scrolls: [Int] = []
    func show(_ presentation: CandidatePresentation) {}
    func showLoading(pinyin: String) {
        loading.append(pinyin)
        let callback = onLoading
        onLoading = nil
        callback?()
    }
    func showModeStatus(mode: InputMode) {}
    func showCaseStatus(uppercaseLocked: Bool) {}
    func scrollHighlightedCandidate(by pages: Int) -> Bool {
        scrolls.append(pages)
        return overflows
    }
    func hide() {}
}

@MainActor private final class BoundaryHost: InputHost {
    let context: String
    var markedText = ""
    var committed: [String] = []
    var onContext: (() -> Void)?
    var onMarked: (() -> Void)?
    init(context: String) { self.context = context }
    func precedingContext() -> String {
        let callback = onContext
        onContext = nil
        callback?()
        return context
    }
    func setMarkedText(_ text: String) {
        markedText = text
        let callback = onMarked
        onMarked = nil
        callback?()
    }
    func commit(_ text: String) { committed.append(text); markedText = "" }
}
