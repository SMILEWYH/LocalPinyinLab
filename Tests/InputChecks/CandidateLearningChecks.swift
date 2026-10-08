import PinyinCore
import PinyinApplication

@MainActor final class CandidateLearningChecks {
    func fullCandidateSelectionLearnsOnce() async throws {
        for usesNumber in [false, true] {
            let fixture = LearningFixture()
            try await fixture.compose("ni")
            try checkTrue(fixture.press(usesNumber ? 19 : 49, usesNumber ? "2" : " "))
            let expected = usesNumber ? "拟" : "你"
            try checkEqual(fixture.host.committed, [expected])
            try fixture.checkLearning(texts: [[expected]], pinyin: [["ni"]])
            fixture.session.finishComposition()
            fixture.session.deactivate()
            try fixture.checkLearning(texts: [[expected]], pinyin: [["ni"]])
            fixture.finish()
        }
    }

    func segmentedSelectionLearnsOnlyTheFinalSegments() async throws {
        let fixture = LearningFixture()
        fixture.provider.segmentFirstCandidate = true
        try await fixture.compose("ni'hao")
        try checkTrue(fixture.press(18, "1"))
        try checkEqual(fixture.session.composition.selectedText, "你")
        try checkEqual(fixture.session.composition.pending, "hao")
        try checkTrue(fixture.provider.learned.isEmpty)
        try checkTrue(fixture.host.committed.isEmpty)
        try await fixture.wait { fixture.session.queryState == .ready }
        try checkTrue(fixture.press(19, "2"))
        try checkEqual(fixture.host.committed, ["你号"])
        try fixture.checkLearning(texts: [["你", "号"]], pinyin: [["ni'", "hao"]])
        fixture.finish()
    }

    func cancellationAndUndoDiscardOldSelections() async throws {
        let cancelled = LearningFixture()
        try await cancelled.selectPrefix()
        try checkTrue(cancelled.press(53))
        try checkTrue(cancelled.provider.learned.isEmpty)
        try checkTrue(cancelled.host.committed.isEmpty)
        try await cancelled.compose("ni")
        try checkTrue(cancelled.press(19, "2"))
        try cancelled.checkLearning(texts: [["拟"]], pinyin: [["ni"]])
        cancelled.finish()

        let undone = LearningFixture()
        try await undone.selectPrefix()
        try checkTrue(undone.press(123, modifiers: .shift))
        try checkTrue(undone.provider.learned.isEmpty)
        try checkTrue(undone.session.composition.segments.isEmpty)
        try await undone.wait { undone.session.queryState == .ready }
        try checkTrue(undone.press(19, "2"))
        try undone.checkLearning(texts: [["你好"]], pinyin: [["nihao"]])
        undone.finish()

        let deleted = LearningFixture()
        try await deleted.selectPrefix()
        // Three deletes remove the suffix; the fourth restores the chosen segment.
        for _ in 0..<4 { try checkTrue(deleted.press(51)) }
        try checkEqual(deleted.session.composition.pending, "ni")
        try checkTrue(deleted.session.composition.segments.isEmpty)
        try checkTrue(deleted.provider.learned.isEmpty)
        try await deleted.wait { deleted.session.queryState == .ready }
        try checkTrue(deleted.press(19, "2"))
        try deleted.checkLearning(texts: [["拟"]], pinyin: [["ni"]])
        deleted.finish()
    }

    func selectedTextWithoutSuffixStillLearns() async throws {
        let fixture = LearningFixture()
        try await fixture.selectPrefix()
        for _ in 0..<3 { try checkTrue(fixture.press(51)) }
        try checkEqual(fixture.session.queryState, .selectedTextOnly)
        try checkTrue(fixture.provider.learned.isEmpty)
        try checkTrue(fixture.press(49, " "))
        try checkEqual(fixture.host.committed, ["你"])
        try fixture.checkLearning(texts: [["你"]], pinyin: [["ni"]])
        fixture.finish()
    }

    func compositionCompletionLearnsOnlyChosenText() async throws {
        for trigger in LearningCommitTrigger.allCases {
            let fixture = LearningFixture()
            try await fixture.selectPrefix()
            try fixture.commit(using: trigger)
            try checkEqual(fixture.host.committed, ["你hao" + trigger.suffix])
            try fixture.checkLearning(texts: [["你"]], pinyin: [["ni"]])
            try checkTrue(fixture.session.composition.isEmpty)
            fixture.finish()
        }
    }

    func rawCompositionAndPunctuationNeverLearn() async throws {
        for trigger in LearningCommitTrigger.allCases {
            let fixture = LearningFixture()
            try await fixture.compose("nihao")
            try fixture.commit(using: trigger)
            try checkEqual(fixture.host.committed, ["nihao" + trigger.suffix])
            try checkTrue(fixture.provider.learned.isEmpty)
            fixture.finish()
        }
        let fixture = LearningFixture()
        try checkTrue(fixture.press(43, ","))
        fixture.session.finishComposition()
        fixture.session.deactivate()
        try checkEqual(fixture.host.committed, ["，"])
        try checkTrue(fixture.provider.learned.isEmpty)
    }

    func reentrantCommitCannotRepeatLearning() async throws {
        for trigger: LearningCommitTrigger in [.finish, .deactivate] {
            let fixture = LearningFixture()
            try await fixture.selectPrefix()
            var compositionWasCleared = false
            var learningCountBeforeHostCommit = 0
            fixture.host.onCommit = { [weak session = fixture.session, provider = fixture.provider] in
                compositionWasCleared = session?.composition.isEmpty == true
                learningCountBeforeHostCommit = provider.learned.count
                session?.finishComposition()
                session?.deactivate()
            }
            try fixture.commit(using: trigger)
            try checkTrue(compositionWasCleared)
            try checkEqual(learningCountBeforeHostCommit, 1)
            try checkEqual(fixture.host.committed, ["你hao"])
            try fixture.checkLearning(texts: [["你"]], pinyin: [["ni"]])
            fixture.finish()
        }
    }

    func queuedSelectionLearnsOnlyTheCurrentQuery() async throws {
        let queued = LearningFixture()
        queued.provider.deferred = true
        try checkTrue(queued.press(45, "ni"))
        try await queued.wait { queued.provider.pending.count == 1 }
        try checkTrue(queued.press(19, "2"))
        try checkTrue(queued.provider.learned.isEmpty)
        queued.provider.complete(0)
        try await queued.wait { !queued.host.committed.isEmpty }
        try checkEqual(queued.host.committed, ["拟"])
        try queued.checkLearning(texts: [["拟"]], pinyin: [["ni"]])
        queued.finish()

        let replaced = LearningFixture()
        replaced.provider.deferred = true
        try checkTrue(replaced.press(45, "n"))
        try await replaced.wait { replaced.provider.pending.count == 1 }
        try checkTrue(replaced.press(49, " "))
        try checkTrue(replaced.press(34, "i"))
        try await replaced.wait { replaced.provider.pending.count == 2 }
        replaced.provider.complete(0)
        for _ in 0..<100 { await Task.yield() }
        try checkEqual(replaced.session.queryState, .querying)
        try checkTrue(replaced.provider.learned.isEmpty)
        try checkTrue(replaced.host.committed.isEmpty)
        replaced.provider.complete(1)
        try await replaced.wait { replaced.session.queryState == .ready }
        try checkTrue(replaced.provider.learned.isEmpty)
        try checkTrue(replaced.host.committed.isEmpty)
        try checkTrue(replaced.press(19, "2"))
        try replaced.checkLearning(texts: [["拟"]], pinyin: [["ni"]])
        replaced.finish()
    }

    func lateCandidatesCannotLearnAfterCancellationOrCommit() async throws {
        for cancels in [false, true] {
            let fixture = LearningFixture()
            fixture.provider.segmentFirstCandidate = true
            try await fixture.compose("nihao")
            fixture.provider.deferred = true
            try checkTrue(fixture.press(49, " "))
            try await fixture.wait { fixture.provider.pending.count == 1 }
            try checkTrue(fixture.press(49, " "))
            try checkTrue(fixture.press(cancels ? 53 : 36))
            let expectedTexts = cancels ? [] : [["你"]]
            let expectedPinyin = cancels ? [] : [["ni"]]
            try fixture.checkLearning(texts: expectedTexts, pinyin: expectedPinyin)
            fixture.provider.complete(1)
            for _ in 0..<100 { await Task.yield() }
            try checkTrue(fixture.session.composition.isEmpty)
            try checkEqual(fixture.session.queryState, .idle)
            try checkEqual(fixture.host.committed, cancels ? [] : ["你hao"])
            try fixture.checkLearning(texts: expectedTexts, pinyin: expectedPinyin)
            fixture.finish()
        }
    }
}

private enum LearningCommitTrigger: CaseIterable {
    case enter, punctuation, capsLock, finish, deactivate
    var suffix: String { self == .punctuation ? "，" : "" }
}

@MainActor private final class LearningFixture {
    let provider = LearningProvider()
    let host = LearningHost()
    let session: InputSession

    init() {
        session = InputSession(provider: provider, translator: LearningTranslator(), speaker: LearningSpeaker(), presenter: LearningPresenter())
        session.activate(capsLock: false)
    }

    func press(_ code: UInt16, _ text: String = "", modifiers: KeyModifiers = []) -> Bool {
        session.handle(KeyStroke(code: code, characters: text, modifiers: modifiers), host: host)
    }

    func compose(_ pinyin: String) async throws {
        try checkTrue(press(45, pinyin))
        try await wait { session.queryState == .ready }
    }

    func selectPrefix() async throws {
        provider.segmentFirstCandidate = true
        try await compose("nihao")
        try checkTrue(press(49, " "))
        try await wait { session.queryState == .ready }
        try checkEqual(session.composition.selectedText, "你")
        try checkEqual(session.composition.pending, "hao")
        try checkTrue(provider.learned.isEmpty)
    }

    func commit(using trigger: LearningCommitTrigger) throws {
        switch trigger {
        case .enter: try checkTrue(press(36))
        case .punctuation: try checkTrue(press(43, ","))
        case .capsLock: try checkTrue(session.handleCapsLock(true, host: host))
        case .finish: session.finishComposition()
        case .deactivate: session.deactivate()
        }
    }

    func checkLearning(texts: [[String]], pinyin: [[String]], file: StaticString = #filePath, line: UInt = #line) throws {
        try checkEqual(provider.learned.map { $0.map(\.text) }, texts, file: file, line: line)
        try checkEqual(provider.learned.map { $0.map(\.pinyin) }, pinyin, file: file, line: line)
    }

    func wait(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !predicate() { await Task.yield() }
        try checkTrue(predicate())
    }

    func finish() {
        session.cancel()
        for index in Array(provider.pending.keys) { provider.complete(index) }
    }
}

@MainActor private final class LearningProvider: CandidateProviding {
    var segmentFirstCandidate = false
    var deferred = false
    var calls: [String] = []
    var pending: [Int: CheckedContinuation<[Candidate], any Error>] = [:]
    var learned: [[CompositionState.Segment]] = []
    func warm() {}
    func recordCommittedSegments(_ segments: [CompositionState.Segment]) { learned.append(segments) }
    func candidates(for pinyin: String, context: String) async throws -> [Candidate] {
        let index = calls.count
        calls.append(pinyin)
        if deferred { return try await withCheckedThrowingContinuation { pending[index] = $0 } }
        return results(for: pinyin)
    }
    private func results(for pinyin: String) -> [Candidate] {
        if segmentFirstCandidate && (pinyin == "nihao" || pinyin == "ni'hao") {
            return [Candidate(text: "你", consumedCount: pinyin == "nihao" ? 2 : 3),
                    Candidate(text: "你好", consumedCount: pinyin.count)]
        }
        let texts = pinyin == "hao" ? ["好", "号"] : ["你", "拟"]
        return texts.map { Candidate(text: $0, consumedCount: pinyin.count) }
    }
    func complete(_ index: Int) { pending.removeValue(forKey: index)?.resume(returning: results(for: calls[index])) }
}

@MainActor private final class LearningTranslator: CandidateTranslating {
    func translate(_ sources: [String], to language: TranslationLanguage) async throws -> [String] { sources }
}

@MainActor private final class LearningSpeaker: SpeechPlaying {
    func speak(_ text: String, language: TranslationLanguage) -> Bool { true }
    func stop() {}
}

@MainActor private final class LearningPresenter: CandidatePresenting {
    func show(_ presentation: CandidatePresentation) {}
    func showLoading(pinyin: String) {}
    func showModeStatus(mode: InputMode) {}
    func showCaseStatus(uppercaseLocked: Bool) {}
    func hide() {}
}

@MainActor private final class LearningHost: InputHost {
    var committed: [String] = []
    var markedText = ""
    var onCommit: (@MainActor () -> Void)?
    func precedingContext() -> String { committed.joined() + markedText }
    func setMarkedText(_ text: String) { markedText = text }
    func commit(_ text: String) {
        committed.append(text)
        markedText = ""
        onCommit?()
    }
}
