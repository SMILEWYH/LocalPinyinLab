import PinyinCore
import PinyinApplication

@MainActor final class PagingChecks {
    func arrowsPageAndStopAtBoundaries() async throws {
        let fixture = PagingFixture()
        try await fixture.compose("ni")
        for (key, page) in [(123, 0), (124, 1), (124, 2), (124, 2), (123, 1), (123, 0), (123, 0)] {
            try checkTrue(fixture.press(UInt16(key)))
            try fixture.checkPage(page)
        }
        try checkEqual(fixture.session.composition.pending, "ni")
        try checkEqual(fixture.host.markedText, "ni")
        try checkTrue(fixture.host.committed.isEmpty)
    }

    func selectionsUseTheDisplayedPage() async throws {
        for usesNumber in [false, true] {
            let fixture = PagingFixture()
            try await fixture.compose("ni")
            try checkTrue(fixture.press(124))
            if usesNumber {
                try checkTrue(fixture.press(124))
                try checkTrue(fixture.press(19, text: "2"))
                try checkEqual(fixture.host.committed, ["词20"])
            } else {
                // Up/down still move the highlight before Space selects it.
                try checkTrue(fixture.press(125))
                try checkEqual(fixture.presenter.presentation?.highlighted, 1)
                try checkTrue(fixture.press(126))
                try checkEqual(fixture.presenter.presentation?.highlighted, 0)
                try checkTrue(fixture.press(49, text: " "))
                try checkEqual(fixture.host.committed, ["词10"])
            }
            try checkTrue(fixture.session.composition.isEmpty)
            try checkTrue(fixture.host.markedText.isEmpty)
        }
    }

    func plainLeftPagesAndShiftLeftUndoesSegments() async throws {
        let fixture = PagingFixture()
        fixture.provider.segmentFirstCandidate = true
        try await fixture.compose("nihao")
        try checkTrue(fixture.press(49, text: " "))
        try await fixture.waitForCandidates()
        try checkEqual(fixture.session.composition.selectedText, "你")
        try checkEqual(fixture.session.composition.pending, "hao")
        try checkTrue(fixture.press(124))
        try checkTrue(fixture.press(123))
        try fixture.checkPage(0)
        try checkEqual(fixture.session.composition.selectedText, "你")
        try checkEqual(fixture.host.markedText, "你hao")
        try checkTrue(fixture.press(123, modifiers: .shift))
        try checkTrue(fixture.session.composition.segments.isEmpty)
        try checkEqual(fixture.session.composition.pending, "nihao")
        try checkEqual(fixture.host.markedText, "nihao")
        // With no earlier segment left, Shift+Left still belongs to the IME.
        try checkTrue(fixture.press(123, modifiers: .shift))
        try checkEqual(fixture.session.composition.pending, "nihao")
        try checkTrue(fixture.host.committed.isEmpty)
    }

    func arrowsDuringLoadingNeverCommit() async throws {
        for (selectionKey, text) in [(19, "2"), (49, " ")] {
            let fixture = PagingFixture()
            fixture.provider.delaysResponse = true
            try checkTrue(fixture.press(45, text: "ni"))
            for _ in 0..<100 where fixture.provider.pendingResponse == nil { await Task.yield() }
            try checkTrue(fixture.provider.pendingResponse != nil)
            // Paging supersedes a number/Space selection queued during loading.
            try checkTrue(fixture.press(UInt16(selectionKey), text: text))
            for key: UInt16 in [123, 124, 124, 123] { try checkTrue(fixture.press(key)) }
            try checkTrue(fixture.press(123, modifiers: .shift))
            try checkEqual(fixture.session.composition.pending, "ni")
            try checkEqual(fixture.host.markedText, "ni")
            try checkTrue(fixture.host.committed.isEmpty)
            fixture.provider.pendingResponse?.resume(returning: PagingProvider.results(for: "ni"))
            fixture.provider.pendingResponse = nil
            try await fixture.waitForCandidates()
            try fixture.checkPage(0)
            try checkEqual(fixture.session.composition.pending, "ni")
            try checkEqual(fixture.host.markedText, "ni")
            try checkTrue(fixture.press(124))
            try fixture.checkPage(1)
            try checkTrue(fixture.host.committed.isEmpty)
        }
    }

    func arrowsPassThroughOutsideCompositionAndWithShortcuts() async throws {
        let fixture = PagingFixture()
        for key: UInt16 in [123, 124] {
            try checkFalse(fixture.press(key))
            try checkFalse(fixture.press(key, modifiers: .shift))
        }
        try checkTrue(fixture.pressCapsLock())
        try checkEqual(fixture.session.mode, .englishDirect)
        for key: UInt16 in [123, 124] {
            try checkFalse(fixture.press(key))
            try checkFalse(fixture.press(key, modifiers: .shift))
        }
        try checkTrue(fixture.pressCapsLock())
        try await fixture.compose("ni")
        for modifiers: KeyModifiers in [.command, .control, .option, [.command, .shift], [.control, .shift], [.option, .shift]] {
            for key: UInt16 in [123, 124] { try checkFalse(fixture.press(key, modifiers: modifiers)) }
        }
        try fixture.checkPage(0)
        try checkEqual(fixture.host.markedText, "ni")
        try checkTrue(fixture.host.committed.isEmpty)
    }

    func controlShiftSpacePreservesComposition() async throws {
        for isLoading in [false, true] {
            let fixture = PagingFixture()
            defer { fixture.session.cancel() }
            fixture.provider.delaysResponse = isLoading
            try checkTrue(fixture.press(45, text: "ni"))
            if isLoading {
                for _ in 0..<100 where fixture.provider.pendingResponse == nil { await Task.yield() }
                try checkTrue(fixture.provider.pendingResponse != nil)
            } else {
                try await fixture.waitForCandidates()
                try checkTrue(fixture.press(124))
                try checkTrue(fixture.press(125))
            }
            let state = fixture.session.queryState
            let page = fixture.session.candidates.page
            let highlight = fixture.session.candidates.highlighted
            let visibleCandidates = fixture.presenter.presentation?.rows.map(\.text)

            try checkFalse(fixture.press(49, text: " ", modifiers: [.control, .shift]))
            try checkEqual(fixture.session.mode, .chinesePinyin)
            try checkEqual(fixture.session.composition.pending, "ni")
            try checkEqual(fixture.host.markedText, "ni")
            try checkEqual(fixture.session.queryState, state)
            try checkEqual(fixture.session.candidates.page, page)
            try checkEqual(fixture.session.candidates.highlighted, highlight)
            try checkEqual(fixture.presenter.presentation?.rows.map(\.text), visibleCandidates)
            try checkTrue(fixture.host.committed.isEmpty)

            if isLoading {
                fixture.provider.pendingResponse?.resume(returning: PagingProvider.results(for: "ni"))
                fixture.provider.pendingResponse = nil
                try await fixture.waitForCandidates()
                // A passed-through Space must not queue a candidate selection.
                try checkEqual(fixture.session.composition.pending, "ni")
                try checkEqual(fixture.host.markedText, "ni")
                try checkTrue(fixture.host.committed.isEmpty)
            }
        }
    }

    func arrowsMatchPageUpAndPageDown() async throws {
        let arrows = PagingFixture()
        let pageKeys = PagingFixture()
        try await arrows.compose("ni")
        try await pageKeys.compose("ni")
        for (arrow, pageKey) in [(124, 121), (124, 121), (124, 121), (123, 116), (123, 116), (123, 116)] {
            try checkTrue(arrows.press(UInt16(arrow)))
            try checkTrue(pageKeys.press(UInt16(pageKey)))
            try checkEqual(arrows.session.candidates.page, pageKeys.session.candidates.page)
            try checkEqual(arrows.session.candidates.highlighted, pageKeys.session.candidates.highlighted)
            try checkEqual(arrows.presenter.presentation?.rows.map(\.text), pageKeys.presenter.presentation?.rows.map(\.text))
        }
        try checkTrue(arrows.host.committed.isEmpty)
        try checkTrue(pageKeys.host.committed.isEmpty)
    }
}

@MainActor private final class PagingFixture {
    let provider = PagingProvider()
    let host = PagingHost()
    let presenter = PagingPresenter()
    let session: InputSession
    private var physicalCapsLock = false

    init() {
        session = InputSession(provider: provider, translator: PagingTranslator(), speaker: PagingSpeaker(), presenter: presenter)
        session.activate(capsLock: false)
    }

    func press(_ code: UInt16, text: String? = nil, modifiers: KeyModifiers = []) -> Bool {
        let specialCharacters: [UInt16: String] = [123: "\u{F702}", 124: "\u{F703}", 125: "\u{F701}", 126: "\u{F700}", 116: "\u{F72C}", 121: "\u{F72D}"]
        let handled = session.handle(KeyStroke(code: code, characters: text ?? specialCharacters[code] ?? "", modifiers: modifiers,
                                               capsLock: physicalCapsLock), host: host)
        physicalCapsLock = session.mode == .englishDirect
        session.acknowledgeCapsLock(physicalCapsLock)
        return handled
    }

    func pressCapsLock() -> Bool {
        physicalCapsLock.toggle()
        return session.handleCapsLock(physicalCapsLock, host: host)
    }

    func compose(_ pinyin: String) async throws {
        try checkTrue(press(45, text: pinyin))
        try await waitForCandidates()
    }

    func waitForCandidates() async throws {
        for _ in 0..<100 where session.candidates.rows.isEmpty { await Task.yield() }
        try checkEqual(session.candidates.rows.count, 20)
    }

    func checkPage(_ page: Int) throws {
        try checkEqual(presenter.presentation?.page, page)
        try checkEqual(presenter.presentation?.totalPages, 3)
        try checkEqual(presenter.presentation?.highlighted, 0)
        try checkEqual(presenter.presentation?.rows.first?.text, "词\(page * 9 + 1)")
        try checkEqual(presenter.presentation?.rows.count, page == 2 ? 2 : 9)
    }
}

@MainActor private final class PagingProvider: CandidateProviding {
    var segmentFirstCandidate = false
    var delaysResponse = false
    var pendingResponse: CheckedContinuation<[Candidate], any Error>?
    func warm() {}
    static func results(for pinyin: String) -> [Candidate] {
        (1...20).map { Candidate(text: "词\($0)", consumedCount: pinyin.count) }
    }
    func candidates(for pinyin: String, context: String) async throws -> [Candidate] {
        if delaysResponse { return try await withCheckedThrowingContinuation { pendingResponse = $0 } }
        var candidates = Self.results(for: pinyin)
        if segmentFirstCandidate && pinyin == "nihao" { candidates[0] = Candidate(text: "你", consumedCount: 2) }
        return candidates
    }
}

@MainActor private final class PagingTranslator: CandidateTranslating {
    func translate(_ sources: [String], to language: TranslationLanguage) async throws -> [String] { sources }
}

@MainActor private final class PagingSpeaker: SpeechPlaying {
    func speak(_ text: String, language: TranslationLanguage) -> Bool { true }
    func stop() {}
}

@MainActor private final class PagingPresenter: CandidatePresenting {
    var presentation: CandidatePresentation?
    func show(_ presentation: CandidatePresentation) { self.presentation = presentation }
    func showLoading(pinyin: String) { presentation = nil }
    func showModeStatus(mode: InputMode) {}
    func showCaseStatus(uppercaseLocked: Bool) {}
    func hide() { presentation = nil }
}

@MainActor private final class PagingHost: InputHost {
    var committed: [String] = []
    var markedText = ""
    func precedingContext() -> String { committed.joined() + markedText }
    func setMarkedText(_ text: String) { markedText = text }
    func commit(_ text: String) { committed.append(text); markedText = "" }
}
