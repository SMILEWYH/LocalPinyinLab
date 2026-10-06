import PinyinCore
import PinyinApplication

@MainActor final class TranslationLanguageChecks {
    func switchingLanguagePreservesCompositionAndPage() async throws {
        let fixture = LanguageFixture()
        defer { fixture.finish() }
        fixture.provider.segmentFirstCandidate = true
        try checkTrue(fixture.press(45, "nihao"))
        try await fixture.wait { fixture.translator.calls.count == 1 }
        try checkTrue(fixture.press(49, " "))
        try await fixture.wait { fixture.translator.calls.count == 2 }
        fixture.translator.complete(1)
        try await fixture.wait { fixture.session.candidates.rows[0].speechText != nil }
        try checkTrue(fixture.press(124))
        try await fixture.wait { fixture.translator.calls.count == 3 }
        fixture.translator.complete(2)
        try await fixture.wait { fixture.session.candidates.rows[9].speechText != nil }
        try checkTrue(fixture.press(125))
        let composition = fixture.session.composition
        let candidates = fixture.session.candidates.rows.map(\.candidate)
        let selection = fixture.session.candidates.selectedIndex
        let queryCount = fixture.provider.queries.count

        fixture.session.setTranslationLanguage(.japanese)
        try checkEqual(fixture.session.composition, composition)
        try checkEqual(fixture.session.composition.selectedText, "你")
        try checkEqual(fixture.host.markedText, "你hao")
        try checkEqual(fixture.session.candidates.rows.map(\.candidate), candidates)
        try checkEqual(fixture.session.candidates.selectedIndex, selection)
        try checkEqual(fixture.session.candidates.page, 1)
        try checkEqual(fixture.provider.queries.count, queryCount)
        try checkTrue(fixture.host.committed.isEmpty)
        try checkTrue(fixture.session.candidates.rows.allSatisfy { $0.translation == .pending })
        try checkEqual(fixture.presenter.presentation?.translationLanguage, .japanese)
        try await fixture.wait { fixture.translator.calls.count == 4 }
        try checkEqual(fixture.translator.calls[3].language, .japanese)
        fixture.translator.complete(3)
        try await fixture.wait { fixture.session.candidates.rows[9].speechText != nil }
        try checkEqual(fixture.session.candidates.rows[9].speechText, "ja:0")
        // A page translated before the switch must also request the new target.
        try checkTrue(fixture.press(123))
        try await fixture.wait { fixture.translator.calls.count == 5 }
        try checkEqual(fixture.translator.calls[4].language, .japanese)
    }

    func returningToLanguageStillRejectsItsOldBatch() async throws {
        let fixture = LanguageFixture()
        defer { fixture.finish() }
        try checkTrue(fixture.press(45, "ni"))
        try await fixture.wait { fixture.translator.calls.count == 1 }
        fixture.session.setTranslationLanguage(.japanese)
        try await fixture.wait { fixture.translator.calls.count == 2 }
        fixture.session.setTranslationLanguage(.english)
        try await fixture.wait { fixture.translator.calls.count == 3 }
        fixture.translator.complete(0, prefix: "obsoleteEnglish")
        fixture.translator.complete(1, prefix: "obsoleteJapanese")
        for _ in 0..<100 { await Task.yield() }
        try checkTrue(fixture.session.candidates.rows.allSatisfy { $0.translation == .pending })
        try checkEqual(fixture.presenter.presentation?.translationLanguage, .english)
        fixture.translator.complete(2, prefix: "currentEnglish")
        try await fixture.wait { fixture.session.candidates.rows[0].speechText != nil }
        try checkEqual(fixture.session.candidates.rows[0].speechText, "currentEnglish:0")
    }

    func languageChangeDuringQueryUsesLatestTarget() async throws {
        let fixture = LanguageFixture(language: .german)
        defer { fixture.finish() }
        fixture.provider.deferred = true
        try checkTrue(fixture.press(45, "ni"))
        try await fixture.wait { fixture.provider.pending != nil }
        fixture.session.setTranslationLanguage(.french)
        try checkEqual(fixture.session.queryState, .querying)
        try checkEqual(fixture.provider.queries, ["ni"])
        try checkTrue(fixture.translator.calls.isEmpty)
        fixture.provider.complete()
        try await fixture.wait { fixture.translator.calls.count == 1 }
        try checkEqual(fixture.translator.calls[0].language, .french)
        try checkEqual(fixture.presenter.presentation?.translationLanguage, .french)
        fixture.translator.complete(0)
        try await fixture.wait { fixture.session.candidates.rows[0].speechText != nil }
        try checkEqual(fixture.session.candidates.rows[0].speechText, "fr:0")
    }

    func speechStopsAndFollowsCurrentLanguage() async throws {
        let fixture = LanguageFixture()
        defer { fixture.finish() }
        try checkTrue(fixture.press(45, "ni"))
        try await fixture.wait { fixture.translator.calls.count == 1 }
        fixture.translator.complete(0)
        try await fixture.wait { fixture.session.candidates.rows[0].speechText != nil }
        try checkTrue(fixture.speak())
        try checkEqual(fixture.speaker.calls.map(\.language), [.english])
        try checkEqual(fixture.speaker.calls.map(\.text), ["en:0"])
        let stops = fixture.speaker.stops
        fixture.session.setTranslationLanguage(.japanese)
        try checkEqual(fixture.speaker.stops, stops + 1)
        try checkFalse(fixture.speaker.isSpeaking)
        try checkFalse(fixture.speak())
        try checkEqual(fixture.speaker.calls.count, 1)
        try await fixture.wait { fixture.translator.calls.count == 2 }
        fixture.translator.complete(1)
        try await fixture.wait { fixture.session.candidates.rows[0].speechText != nil }
        fixture.speaker.available = false
        try checkTrue(fixture.speak())
        try checkEqual(fixture.speaker.calls.map(\.language), [.english, .japanese])
        try checkEqual(fixture.speaker.calls.last?.text, "ja:0")
        try checkEqual(fixture.presenter.presentation?.status, "未找到本地\(TranslationLanguage.japanese.displayName)声音")
    }

    func selectingSameLanguageDoesNotRestartWork() async throws {
        let fixture = LanguageFixture()
        defer { fixture.finish() }
        try checkTrue(fixture.press(45, "ni"))
        try await fixture.wait { fixture.translator.calls.count == 1 }
        let stops = fixture.speaker.stops
        fixture.session.setTranslationLanguage(.english)
        for _ in 0..<100 { await Task.yield() }
        try checkEqual(fixture.translator.calls.count, 1)
        try checkEqual(fixture.speaker.stops, stops)
        fixture.translator.complete(0)
        try await fixture.wait { fixture.session.candidates.rows[0].speechText != nil }
        try checkTrue(fixture.speak())
        let speakingStops = fixture.speaker.stops
        fixture.session.setTranslationLanguage(.english)
        try checkTrue(fixture.speaker.isSpeaking)
        try checkEqual(fixture.speaker.stops, speakingStops)
        try checkEqual(fixture.session.candidates.rows[0].speechText, "en:0")
        try checkEqual(fixture.provider.queries.count, 1)
        try checkEqual(fixture.translator.calls.count, 1)
    }

    func resetTranslationsPreservesSelectionAndEngineDiagnostics() throws {
        var list = CandidateList(rows: [
            CandidateRow(candidate: Candidate(text: "你", consumedCount: 2), translation: .ready("you")),
            CandidateRow(candidate: Candidate(text: "好", consumedCount: 3), translation: .unavailable(.modelsNotInstalled)),
            CandidateRow(candidate: Candidate(text: "ni", consumedCount: 2), translation: .unavailable(.engineUnavailable)),
            CandidateRow(candidate: Candidate(text: "abc", consumedCount: 3))
        ])
        list.move(by: 1)
        list.resetTranslations()
        try checkEqual(list.selectedIndex, 1)
        try checkEqual(list.rows.map(\.translation), [.pending, .pending, .unavailable(.engineUnavailable), .notRequired])
    }

    func cacheSeparatesTargetsAndKeepsResponseOrder() async throws {
        let backend = LanguageBackend()
        let service = TranslationService(backend: backend)
        let sources = ["你", "好", "你"]
        try checkEqual(try await service.translate(sources, to: .english), ["en:你", "en:好", "en:你"])
        try checkEqual(try await service.translate(sources, to: .japanese), ["ja:你", "ja:好", "ja:你"])
        try checkEqual(try await service.translate(sources, to: .english), ["en:你", "en:好", "en:你"])
        try checkEqual(try await service.translate(sources, to: .japanese), ["ja:你", "ja:好", "ja:你"])
        try checkEqual(backend.calls.map(\.language), [.english, .japanese])
        try checkEqual(backend.calls.map { $0.requests.count }, [2, 2])
    }

    func cancelledBatchCannotFillAnotherLanguagesCache() async throws {
        let backend = LanguageBackend()
        backend.deferred = true
        let service = TranslationService(backend: backend)
        let old = Task { try await service.translate(["你"], to: .english) }
        try await waitForLanguageCheck { backend.calls.count == 1 }
        old.cancel()
        let current = Task { try await service.translate(["你"], to: .japanese) }
        try await waitForLanguageCheck { backend.calls.count == 2 }
        backend.complete(1)
        try checkEqual(try await current.value, ["ja:你"])
        backend.complete(0)
        do {
            _ = try await old.value
            try checkTrue(false)
        } catch is CancellationError { }
        let retry = Task { try await service.translate(["你"], to: .english) }
        try await waitForLanguageCheck { backend.calls.count == 3 }
        backend.complete(2)
        try checkEqual(try await retry.value, ["en:你"])
        try checkEqual(try await service.translate(["你"], to: .japanese), ["ja:你"])
        try checkEqual(backend.calls.map(\.language), [.english, .japanese, .english])
    }
}

@MainActor private func waitForLanguageCheck(_ predicate: @MainActor () -> Bool) async throws {
    for _ in 0..<200 where !predicate() { await Task.yield() }
    try checkTrue(predicate())
}

@MainActor private final class LanguageFixture {
    let provider = LanguageCandidateProvider()
    let translator = LanguageTranslator()
    let speaker = LanguageSpeaker()
    let host = LanguageHost()
    let presenter = LanguagePresenter()
    let session: InputSession

    init(language: TranslationLanguage = .english) {
        session = InputSession(provider: provider, translator: translator, speaker: speaker, presenter: presenter,
                               translationLanguage: language)
        session.activate(capsLock: false)
    }

    func press(_ code: UInt16, _ text: String = "") -> Bool {
        session.handle(KeyStroke(code: code, characters: text), host: host)
    }
    func speak() -> Bool {
        _ = session.handleSpeechModifiers([.command], host: host)
        _ = session.handleSpeechModifiers([.command, .option], host: host)
        return session.handleSpeechModifiers([], host: host)
    }
    func wait(_ predicate: @MainActor () -> Bool) async throws { try await waitForLanguageCheck(predicate) }
    func finish() {
        session.cancel()
        provider.complete()
        for index in Array(translator.pending.keys) { translator.complete(index) }
    }
}

@MainActor private final class LanguageCandidateProvider: CandidateProviding {
    var queries: [String] = []
    var deferred = false
    var segmentFirstCandidate = false
    var pending: CheckedContinuation<[Candidate], any Error>?
    func warm() {}
    func candidates(for pinyin: String, context: String) async throws -> [Candidate] {
        queries.append(pinyin)
        if deferred { return try await withCheckedThrowingContinuation { pending = $0 } }
        return results(for: pinyin)
    }
    private func results(for pinyin: String) -> [Candidate] {
        var result = (1...20).map { Candidate(text: "词\($0)", consumedCount: pinyin.count) }
        if segmentFirstCandidate && pinyin == "nihao" { result[0] = Candidate(text: "你", consumedCount: 2) }
        return result
    }
    func complete() {
        guard let response = pending, let query = queries.last else { return }
        pending = nil
        response.resume(returning: results(for: query))
    }
}

@MainActor private final class LanguageTranslator: CandidateTranslating {
    struct Call { let sources: [String]; let language: TranslationLanguage }
    var calls: [Call] = []
    var pending: [Int: CheckedContinuation<[String], any Error>] = [:]
    func translate(_ sources: [String], to language: TranslationLanguage) async throws -> [String] {
        let index = calls.count
        calls.append(Call(sources: sources, language: language))
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func complete(_ index: Int, prefix: String? = nil) {
        let call = calls[index]
        let result = call.sources.indices.map { "\(prefix ?? call.language.rawValue):\($0)" }
        pending.removeValue(forKey: index)?.resume(returning: result)
    }
}

@MainActor private final class LanguageSpeaker: SpeechPlaying {
    struct Call { let text: String; let language: TranslationLanguage }
    var calls: [Call] = []
    var stops = 0
    var available = true
    var isSpeaking = false
    func speak(_ text: String, language: TranslationLanguage) -> Bool {
        calls.append(Call(text: text, language: language))
        isSpeaking = available
        return available
    }
    func stop() { stops += 1; isSpeaking = false }
}

@MainActor private final class LanguageHost: InputHost {
    var markedText = ""
    var committed: [String] = []
    func precedingContext() -> String { committed.joined() + markedText }
    func setMarkedText(_ text: String) { markedText = text }
    func commit(_ text: String) { committed.append(text); markedText = "" }
}

@MainActor private final class LanguagePresenter: CandidatePresenting {
    var presentation: CandidatePresentation?
    func show(_ presentation: CandidatePresentation) { self.presentation = presentation }
    func showLoading(pinyin: String) { presentation = nil }
    func showModeStatus(mode: InputMode) { presentation = nil }
    func showCaseStatus(uppercaseLocked: Bool) { presentation = nil }
    func hide() { presentation = nil }
}

@MainActor private final class LanguageBackend: TranslationBackend {
    struct Call { let requests: [TranslationRequest]; let language: TranslationLanguage }
    var calls: [Call] = []
    var deferred = false
    var pending: [Int: CheckedContinuation<[TranslationResponse], any Error>] = [:]
    func translations(for requests: [TranslationRequest], to language: TranslationLanguage) async throws -> [TranslationResponse] {
        let index = calls.count
        calls.append(Call(requests: requests, language: language))
        if deferred { return try await withCheckedThrowingContinuation { pending[index] = $0 } }
        return results(index)
    }
    private func results(_ index: Int) -> [TranslationResponse] {
        let call = calls[index]
        return call.requests.reversed().map {
            TranslationResponse(identifier: $0.identifier, text: "\(call.language.rawValue):\($0.source)")
        }
    }
    func complete(_ index: Int) { pending.removeValue(forKey: index)?.resume(returning: results(index)) }
}
