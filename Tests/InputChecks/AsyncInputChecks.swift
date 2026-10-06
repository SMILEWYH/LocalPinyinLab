import PinyinCore
import PinyinApplication

@MainActor final class AsyncInputChecks {
    func verticalNavigationWhileLoadingPreservesComposition() async throws {
        for code: UInt16 in [125, 126] {
            let fixture = AsyncInputFixture()
            fixture.provider.deferred = true
            try checkEqual(fixture.session.queryState, .idle)
            try checkTrue(fixture.press(45, "ni"))
            try await fixture.wait { fixture.provider.pending.count == 1 }
            try checkTrue(fixture.press(49, " "))
            try checkTrue(fixture.press(code))
            try checkEqual(fixture.session.queryState, .querying)
            try checkEqual(fixture.host.markedText, "ni")
            try checkTrue(fixture.host.committed.isEmpty)
            try checkEqual(fixture.presenter.loading, "ni")
            fixture.provider.complete(0)
            try await fixture.wait { fixture.session.queryState == .ready }
            try checkTrue(fixture.host.committed.isEmpty)
            try checkEqual(fixture.session.candidates.selectedIndex, 0)
            fixture.finish()
        }
    }

    func spaceCommitsSelectedTextAfterDeletingSuffix() async throws {
        let fixture = AsyncInputFixture()
        fixture.provider.segmentFirstCandidate = true
        try checkTrue(fixture.press(45, "nihao"))
        try await fixture.wait { fixture.session.queryState == .ready }
        try checkTrue(fixture.press(49, " "))
        try checkEqual(fixture.session.composition.selectedText, "你")
        try checkEqual(fixture.session.composition.pending, "hao")
        for _ in 0..<3 { try checkTrue(fixture.press(51)) }
        try checkEqual(fixture.session.queryState, .selectedTextOnly)
        for code: UInt16 in [123, 124, 125, 126] { try checkTrue(fixture.press(code)) }
        try checkEqual(fixture.host.markedText, "你")
        try checkTrue(fixture.press(49, " "))
        try checkEqual(fixture.host.committed, ["你"])
        try checkEqual(fixture.session.queryState, .idle)
        try checkTrue(fixture.session.composition.isEmpty)
        try checkFalse(fixture.press(49, " "))
        fixture.finish()
    }

    func samePageNavigationRetainsTranslationRequest() async throws {
        let fixture = AsyncInputFixture()
        try checkTrue(fixture.press(45, "ni"))
        try await fixture.wait { fixture.translator.calls.count == 1 }
        // A boundary page key and three highlight moves keep the first batch.
        try checkTrue(fixture.press(123))
        for _ in 0..<3 { try checkTrue(fixture.press(125)) }
        for _ in 0..<100 { await Task.yield() }
        try checkEqual(fixture.translator.calls.count, 1)
        try checkEqual(fixture.session.candidates.page, 0)
        fixture.translator.complete(0, prefix: "first")
        try await fixture.wait { fixture.session.candidates.rows[0].speechText != nil }
        try checkEqual(fixture.session.candidates.rows[0].speechText, "first0")
        try checkTrue(fixture.press(126))
        for _ in 0..<100 { await Task.yield() }
        try checkEqual(fixture.translator.calls.count, 1)
        fixture.finish()
    }

    func changedPageRejectsLateTranslation() async throws {
        let fixture = AsyncInputFixture()
        try checkTrue(fixture.press(45, "ni"))
        try await fixture.wait { fixture.translator.calls.count == 1 }
        try checkTrue(fixture.press(124))
        try await fixture.wait { fixture.translator.calls.count == 2 }
        fixture.translator.complete(0, prefix: "obsolete")
        for _ in 0..<100 { await Task.yield() }
        try checkEqual(fixture.session.candidates.page, 1)
        try checkEqual(fixture.session.candidates.rows[0].translation, .pending)
        fixture.translator.complete(1, prefix: "pageTwo")
        try await fixture.wait { fixture.session.candidates.rows[9].speechText != nil }
        try checkEqual(fixture.session.candidates.rows[9].speechText, "pageTwo0")
        try checkTrue(fixture.press(123))
        try await fixture.wait { fixture.translator.calls.count == 3 }
        fixture.translator.complete(2, prefix: "pageOne")
        try await fixture.wait { fixture.session.candidates.rows[0].speechText != nil }
        try checkTrue(fixture.press(124))
        for _ in 0..<100 { await Task.yield() }
        try checkEqual(fixture.translator.calls.count, 3)
        try checkEqual(fixture.session.candidates.rows[9].speechText, "pageTwo0")
        fixture.finish()
    }

    func changedQueryRejectsLateCandidatesAndTranslation() async throws {
        let fixture = AsyncInputFixture()
        fixture.provider.deferred = true
        try checkTrue(fixture.press(45, "n"))
        try await fixture.wait { fixture.provider.pending.count == 1 }
        try checkTrue(fixture.press(34, "i"))
        try await fixture.wait { fixture.provider.pending.count == 2 }
        fixture.provider.complete(0)
        for _ in 0..<100 { await Task.yield() }
        try checkEqual(fixture.session.queryState, .querying)
        try checkEqual(fixture.presenter.loading, "ni")
        fixture.provider.complete(1)
        try await fixture.wait { fixture.translator.calls.count == 1 }
        try checkTrue(fixture.press(0, "hao"))
        try await fixture.wait { fixture.provider.pending.count == 1 }
        fixture.provider.complete(2)
        try await fixture.wait { fixture.translator.calls.count == 2 }
        fixture.translator.complete(0, prefix: "obsolete")
        for _ in 0..<100 { await Task.yield() }
        try checkEqual(fixture.session.candidates.rows[0].translation, .pending)
        fixture.translator.complete(1, prefix: "current")
        try await fixture.wait { fixture.session.candidates.rows[0].speechText != nil }
        try checkEqual(fixture.session.composition.pending, "nihao")
        try checkEqual(fixture.session.candidates.rows[0].speechText, "current0")
        fixture.finish()
    }

    func failedTranslationIsNotRetriedByHighlightChanges() async throws {
        let fixture = AsyncInputFixture()
        try checkTrue(fixture.press(45, "ni"))
        try await fixture.wait { fixture.translator.calls.count == 1 }
        fixture.translator.fail(0)
        try await fixture.wait { fixture.session.candidates.rows[0].translation == .unavailable(.modelsNotInstalled) }
        try checkTrue(fixture.press(125))
        try checkTrue(fixture.press(123))
        for _ in 0..<100 { await Task.yield() }
        try checkEqual(fixture.translator.calls.count, 1)
        fixture.finish()
    }
}

@MainActor private final class AsyncInputFixture {
    let provider = DeferredCandidateProvider()
    let translator = DeferredTranslator()
    let host = AsyncInputHost()
    let presenter = AsyncInputPresenter()
    let session: InputSession

    init() {
        session = InputSession(provider: provider, translator: translator, speaker: AsyncInputSpeaker(), presenter: presenter)
        session.activate(capsLock: false)
    }

    func press(_ code: UInt16, _ text: String = "") -> Bool {
        let navigation: [UInt16: String] = [123: "\u{F702}", 124: "\u{F703}", 125: "\u{F701}", 126: "\u{F700}"]
        return session.handle(KeyStroke(code: code, characters: navigation[code] ?? text), host: host)
    }

    func wait(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !predicate() { await Task.yield() }
        try checkTrue(predicate())
    }

    func finish() {
        session.cancel()
        for index in Array(provider.pending.keys) { provider.complete(index) }
        for index in Array(translator.pending.keys) { translator.complete(index, prefix: "cleanup") }
    }
}

@MainActor private final class DeferredCandidateProvider: CandidateProviding {
    var deferred = false
    var segmentFirstCandidate = false
    var calls: [String] = []
    var pending: [Int: CheckedContinuation<[Candidate], any Error>] = [:]
    func warm() {}
    func candidates(for pinyin: String, context: String) async throws -> [Candidate] {
        let index = calls.count
        calls.append(pinyin)
        if deferred { return try await withCheckedThrowingContinuation { pending[index] = $0 } }
        return results(for: pinyin)
    }
    private func results(for pinyin: String) -> [Candidate] {
        var result = (1...20).map { Candidate(text: "词\($0)", consumedCount: pinyin.count) }
        if segmentFirstCandidate && pinyin == "nihao" { result[0] = Candidate(text: "你", consumedCount: 2) }
        return result
    }
    func complete(_ index: Int) { pending.removeValue(forKey: index)?.resume(returning: results(for: calls[index])) }
}

@MainActor private final class DeferredTranslator: CandidateTranslating {
    var calls: [[String]] = []
    var pending: [Int: CheckedContinuation<[String], any Error>] = [:]
    func translate(_ sources: [String], to language: TranslationLanguage) async throws -> [String] {
        let index = calls.count
        calls.append(sources)
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func complete(_ index: Int, prefix: String) {
        pending.removeValue(forKey: index)?.resume(returning: calls[index].indices.map { "\(prefix)\($0)" })
    }
    func fail(_ index: Int) { pending.removeValue(forKey: index)?.resume(throwing: TranslationFailure.modelsNotInstalled) }
}

@MainActor private final class AsyncInputSpeaker: SpeechPlaying {
    func speak(_ text: String, language: TranslationLanguage) -> Bool { true }
    func stop() {}
}

@MainActor private final class AsyncInputPresenter: CandidatePresenting {
    var loading: String?
    func show(_ presentation: CandidatePresentation) { loading = nil }
    func showLoading(pinyin: String) { loading = pinyin }
    func showModeStatus(mode: InputMode) { loading = nil }
    func showCaseStatus(uppercaseLocked: Bool) { loading = nil }
    func hide() { loading = nil }
}

@MainActor private final class AsyncInputHost: InputHost {
    var committed: [String] = []
    var markedText = ""
    func precedingContext() -> String { committed.joined() + markedText }
    func setMarkedText(_ text: String) { markedText = text }
    func commit(_ text: String) { committed.append(text); markedText = "" }
}
