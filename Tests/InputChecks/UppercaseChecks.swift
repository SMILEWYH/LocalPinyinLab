import PinyinCore
import PinyinApplication

@MainActor final class UppercaseChecks {
    func togglesFromBothModesAndCapsStates() throws {
        for capsLock in [false, true] {
            let fixture = UppercaseFixture(capsLock: capsLock)
            try checkTrue(fixture.pressCapsLock(modifiers: .shift))
            try checkEqual(fixture.session.mode, .englishDirect)
            try checkTrue(fixture.session.isUppercaseLocked)
            try checkTrue(fixture.pressCapsLock(modifiers: .shift))
            try checkEqual(fixture.session.mode, .englishDirect)
            try checkFalse(fixture.session.isUppercaseLocked)
            try checkEqual(fixture.presenter.caseStatuses, [true, false])
            try checkTrue(fixture.host.committed.isEmpty)
            try checkTrue(fixture.host.markedText.isEmpty)
        }
    }

    func repeatedEventsDoNotToggleOrRepeatStatus() throws {
        for capsLock in [false, true] {
            let fixture = UppercaseFixture(capsLock: capsLock)
            try checkTrue(fixture.pressCapsLock(modifiers: .shift))
            try checkFalse(fixture.session.handleCapsLock(true, modifiers: .shift, host: fixture.host))
            try checkFalse(fixture.session.handleCapsLock(true, host: fixture.host))
            try checkTrue(fixture.host.committed.isEmpty)
            fixture.type("A")
            fixture.type("B", isRepeat: true)
            try checkEqual(fixture.host.committed, ["A", "B"])
            try checkTrue(fixture.session.isUppercaseLocked)
            try checkEqual(fixture.session.mode, .englishDirect)
            try checkEqual(fixture.presenter.caseStatuses, [true])
        }
    }

    func uppercaseSurvivesHostAndSessionChanges() throws {
        let state = InputModeState()
        let fixture = UppercaseFixture(state: state)
        try checkTrue(fixture.pressCapsLock(modifiers: .shift))
        fixture.type("A", capsLock: true)
        let nextHost = UppercaseHost()
        fixture.type("B", capsLock: true, host: nextHost)
        fixture.session.deactivate()
        fixture.session.activate(capsLock: true)
        fixture.type("C", capsLock: true)
        let nextSession = UppercaseFixture(capsLock: true, state: state)
        nextSession.type("D", capsLock: true)
        try checkEqual(fixture.host.committed, ["A", "C"])
        try checkEqual(nextHost.committed, ["B"])
        try checkEqual(nextSession.host.committed, ["D"])
        try checkTrue(nextSession.session.isUppercaseLocked)
        try checkEqual(nextSession.session.mode, .englishDirect)
        try checkEqual(fixture.presenter.caseStatuses, [true])
        try checkTrue(nextSession.presenter.caseStatuses.isEmpty)
    }

    func keyDownRecoversMissedCapsEvent() throws {
        for initialCaps in [false, true] {
            let fixture = UppercaseFixture(capsLock: initialCaps)
            let observedCaps = !initialCaps
            fixture.type("N", capsLock: observedCaps, modifiers: .shift)
            try checkFalse(fixture.session.handleCapsLock(observedCaps, modifiers: .shift, host: fixture.host))
            let expectedMode: InputMode = observedCaps ? .englishDirect : .chinesePinyin
            try checkEqual(fixture.session.mode, expectedMode)
            try checkFalse(fixture.session.isUppercaseLocked)
            try checkEqual(fixture.host.committed, ["N"])
            try checkTrue(fixture.presenter.caseStatuses.isEmpty)
            try checkEqual(fixture.presenter.modeStatuses, [expectedMode])
        }
    }

    func returningToChineseClearsUppercase() throws {
        let fixture = UppercaseFixture()
        try checkTrue(fixture.pressCapsLock(modifiers: .shift))
        try checkTrue(fixture.pressCapsLock())
        try checkEqual(fixture.session.mode, .chinesePinyin)
        try checkFalse(fixture.session.isUppercaseLocked)
        try checkTrue(fixture.pressCapsLock())
        fixture.type("A")
        try checkEqual(fixture.host.committed, ["a"])
        try checkEqual(fixture.session.mode, .englishDirect)
        try checkFalse(fixture.session.isUppercaseLocked)
    }

    func onlyLettersChangeAndShortcutsPassThrough() throws {
        let fixture = UppercaseFixture(capsLock: true)
        try checkTrue(fixture.pressCapsLock(modifiers: .shift))
        fixture.type("A")
        fixture.type("Z")
        fixture.type("B", modifiers: .shift)
        try checkEqual(fixture.host.committed, ["A", "Z", "B"])
        let unchanged = ["1", " ", ",", ".", "!", "@", "'", "\"", "é", "中", "🙂"]
        for text in unchanged {
            try checkFalse(fixture.session.handle(KeyStroke(code: 0, characters: text, capsLock: true), host: fixture.host))
        }
        for modifiers: KeyModifiers in [.command, .control, .option, [.command, .shift], [.control, .shift], [.option, .shift]] {
            try checkFalse(fixture.session.handle(KeyStroke(code: 0, characters: "a", modifiers: modifiers, capsLock: true), host: fixture.host))
        }
        try checkEqual(fixture.host.committed, ["A", "Z", "B"])
        try checkTrue(fixture.session.composition.isEmpty)
        try checkEqual(fixture.presenter.caseStatuses, [true])
        try checkTrue(fixture.pressCapsLock(modifiers: .shift))
        fixture.type("C", capsLock: true)
        fixture.type("D", capsLock: true, modifiers: .shift)
        try checkEqual(fixture.host.committed, ["A", "Z", "B", "c", "D"])
    }

    func toggleCommitsOnceAndRejectsLateCandidates() async throws {
        let fixture = UppercaseFixture()
        fixture.provider.delaysResponse = true
        try checkTrue(fixture.session.handle(KeyStroke(code: 45, characters: "ni"), host: fixture.host))
        for _ in 0..<100 where fixture.provider.pendingResponse == nil { await Task.yield() }
        try checkTrue(fixture.provider.pendingResponse != nil)
        try checkTrue(fixture.pressCapsLock(modifiers: .shift))
        try checkFalse(fixture.session.handleCapsLock(true, modifiers: .shift, host: fixture.host))
        try checkEqual(fixture.host.committed, ["ni"])
        try checkTrue(fixture.host.markedText.isEmpty)
        try checkEqual(fixture.presenter.caseStatuses, [true])
        try checkFalse(fixture.presenter.candidatesVisible)
        fixture.provider.pendingResponse?.resume(returning: [Candidate(text: "你", consumedCount: 2)])
        fixture.provider.pendingResponse = nil
        for _ in 0..<100 { await Task.yield() }
        try checkEqual(fixture.host.committed, ["ni"])
        try checkTrue(fixture.session.composition.isEmpty)
        try checkTrue(fixture.session.candidates.rows.isEmpty)
        try checkFalse(fixture.presenter.candidatesVisible)
        try checkEqual(fixture.presenter.caseStatuses, [true])
    }

    func reentrantCommitCannotShowObsoleteStatus() throws {
        for action in 0..<3 {
            let fixture = UppercaseFixture()
            try checkTrue(fixture.session.handle(KeyStroke(code: 45, characters: "ni"), host: fixture.host))
            fixture.host.onCommit = {
                switch action {
                case 0:
                    _ = fixture.session.handleCapsLock(false, host: fixture.host)
                case 1:
                    fixture.session.cancel()
                default:
                    _ = fixture.session.handle(KeyStroke(code: 0, capsLock: true), host: UppercaseHost())
                    _ = fixture.session.handle(KeyStroke(code: 0, capsLock: true), host: fixture.host)
                }
            }
            try checkTrue(fixture.pressCapsLock(modifiers: .shift))
            try checkEqual(fixture.host.committed, ["ni"])
            try checkTrue(fixture.presenter.caseStatuses.isEmpty)
        }
    }

    func modeStatusAppearsOnceForEachTransition() throws {
        let fixture = UppercaseFixture()
        try checkTrue(fixture.presenter.modeStatuses.isEmpty)
        try checkTrue(fixture.pressCapsLock())
        try checkFalse(fixture.session.handleCapsLock(true, host: fixture.host))
        try checkEqual(fixture.presenter.modeStatuses, [.englishDirect])
        try checkTrue(fixture.pressCapsLock())
        try checkFalse(fixture.session.handleCapsLock(false, host: fixture.host))
        try checkEqual(fixture.presenter.modeStatuses, [.englishDirect, .chinesePinyin])
        fixture.session.deactivate()
        fixture.session.activate(capsLock: false)
        try checkEqual(fixture.presenter.modeStatuses, [.englishDirect, .chinesePinyin])
        try checkTrue(fixture.presenter.caseStatuses.isEmpty)
    }

    func modeStatusSurvivesLateCandidates() async throws {
        let fixture = UppercaseFixture()
        fixture.provider.delaysResponse = true
        try checkTrue(fixture.session.handle(KeyStroke(code: 45, characters: "ni"), host: fixture.host))
        for _ in 0..<100 where fixture.provider.pendingResponse == nil { await Task.yield() }
        try checkTrue(fixture.provider.pendingResponse != nil)
        try checkTrue(fixture.pressCapsLock())
        fixture.provider.pendingResponse?.resume(returning: [Candidate(text: "你", consumedCount: 2)])
        fixture.provider.pendingResponse = nil
        for _ in 0..<100 { await Task.yield() }
        try checkEqual(fixture.host.committed, ["ni"])
        try checkEqual(fixture.session.queryState, .idle)
        try checkTrue(fixture.session.candidates.rows.isEmpty)
        try checkFalse(fixture.presenter.candidatesVisible)
        try checkEqual(fixture.presenter.modeStatuses, [.englishDirect])
    }

    func reentrantCommitCannotShowObsoleteMode() throws {
        for action in 0..<3 {
            let fixture = UppercaseFixture()
            try checkTrue(fixture.session.handle(KeyStroke(code: 45, characters: "ni"), host: fixture.host))
            fixture.host.onCommit = {
                switch action {
                case 0:
                    _ = fixture.session.handleCapsLock(false, host: fixture.host)
                case 1:
                    fixture.session.cancel()
                default:
                    _ = fixture.session.handle(KeyStroke(code: 0, capsLock: true), host: UppercaseHost())
                    _ = fixture.session.handle(KeyStroke(code: 0, capsLock: true), host: fixture.host)
                }
            }
            try checkTrue(fixture.pressCapsLock())
            try checkEqual(fixture.host.committed, ["ni"])
            try checkEqual(fixture.presenter.modeStatuses, action == 0 ? [.chinesePinyin] : [])
        }
    }

    func activationAndRestartFollowPhysicalCaps() throws {
        for capsLock in [false, true] {
            let fixture = UppercaseFixture(capsLock: capsLock)
            let expected: InputMode = capsLock ? .englishDirect : .chinesePinyin
            try checkEqual(fixture.session.mode, expected)
            try checkFalse(fixture.session.isUppercaseLocked)
            try checkTrue(fixture.presenter.modeStatuses.isEmpty)
            try checkFalse(fixture.session.handleCapsLock(capsLock, host: fixture.host))
            fixture.session.deactivate()
            fixture.session.activate(capsLock: !capsLock)
            try checkEqual(fixture.session.mode, capsLock ? .chinesePinyin : .englishDirect)
            try checkTrue(fixture.presenter.modeStatuses.isEmpty)
            let restarted = UppercaseFixture(capsLock: !capsLock)
            try checkEqual(restarted.session.mode, fixture.session.mode)
            try checkFalse(restarted.session.isUppercaseLocked)
        }
    }

    func ordinaryCapsStaysAlignedAfterModeAndUppercaseChanges() throws {
        for capsLock in [false, true] {
            let fixture = UppercaseFixture(capsLock: capsLock)
            try checkTrue(fixture.pressCapsLock())
            try checkEqual(fixture.physicalCapsLock, !capsLock)
            try checkTrue(fixture.pressCapsLock())
            try checkEqual(fixture.session.mode, capsLock ? .englishDirect : .chinesePinyin)
            try checkEqual(fixture.physicalCapsLock, capsLock)
            try checkTrue(fixture.pressCapsLock())
            try checkEqual(fixture.session.mode, capsLock ? .chinesePinyin : .englishDirect)
            try checkTrue(fixture.pressCapsLock(modifiers: .shift))
            try checkTrue(fixture.session.isUppercaseLocked)
            try checkTrue(fixture.physicalCapsLock)
            try checkTrue(fixture.pressCapsLock())
            try checkEqual(fixture.session.mode, .chinesePinyin)
            try checkFalse(fixture.session.isUppercaseLocked)
            try checkFalse(fixture.physicalCapsLock)
        }
    }

    func modifiedCapsAlignsWithoutStealingShortcuts() throws {
        for modifiers: KeyModifiers in [.command, .control, .option, [.command, .shift], [.control, .shift], [.option, .shift]] {
            let fixture = UppercaseFixture()
            try checkTrue(fixture.pressCapsLock(modifiers: modifiers))
            try checkEqual(fixture.session.mode, .englishDirect)
            try checkFalse(fixture.session.isUppercaseLocked)
            try checkFalse(fixture.session.handle(KeyStroke(code: 0, characters: "a", modifiers: modifiers, capsLock: true), host: fixture.host))
            try checkTrue(fixture.pressCapsLock(modifiers: modifiers))
            try checkEqual(fixture.session.mode, .chinesePinyin)
            try checkFalse(fixture.session.handle(KeyStroke(code: 0, characters: "a", modifiers: modifiers), host: fixture.host))
            try checkTrue(fixture.presenter.caseStatuses.isEmpty)
            try checkTrue(fixture.host.committed.isEmpty)
        }
    }

    func hardwareAcknowledgementOnlyChangesBaseline() throws {
        let fixture = UppercaseFixture(capsLock: true)
        try checkTrue(fixture.pressCapsLock(modifiers: .shift))
        try checkEqual(fixture.presenter.caseStatuses, [true])
        fixture.session.acknowledgeCapsLock(false)
        try checkEqual(fixture.session.mode, .englishDirect)
        try checkTrue(fixture.session.isUppercaseLocked)
        try checkFalse(fixture.session.handleCapsLock(false, modifiers: .shift, host: fixture.host))
        try checkEqual(fixture.presenter.caseStatuses, [true])
        try checkTrue(fixture.presenter.modeStatuses.isEmpty)
        // A real-state synchronization is deliberately stronger than an echo
        // acknowledgement; it also recovers a failed hardware write.
        fixture.session.synchronizeCapsLock(false)
        try checkEqual(fixture.session.mode, .chinesePinyin)
        try checkFalse(fixture.session.isUppercaseLocked)
    }

    func sharedSessionsAdoptExternalCapsChanges() throws {
        let state = InputModeState()
        let first = UppercaseFixture(state: state)
        try checkTrue(first.pressCapsLock(modifiers: .shift))
        let second = UppercaseFixture(capsLock: true, state: state)
        try checkTrue(second.session.isUppercaseLocked)
        second.session.deactivate()
        second.session.activate(capsLock: false)
        try checkEqual(first.session.mode, .chinesePinyin)
        try checkFalse(first.session.isUppercaseLocked)
        let restarted = UppercaseFixture(capsLock: true)
        try checkEqual(restarted.session.mode, .englishDirect)
        try checkFalse(restarted.session.isUppercaseLocked)
    }
}

@MainActor private final class UppercaseFixture {
    let provider = UppercaseProvider()
    let host = UppercaseHost()
    let presenter = UppercasePresenter()
    let session: InputSession
    private(set) var physicalCapsLock: Bool

    init(capsLock: Bool = false, state: InputModeState = InputModeState()) {
        physicalCapsLock = capsLock
        session = InputSession(provider: provider, translator: UppercaseTranslator(), speaker: UppercaseSpeaker(),
                               presenter: presenter, modeState: state)
        session.activate(capsLock: capsLock)
    }

    func synchronizeHardware() {
        physicalCapsLock = session.mode == .englishDirect
        session.acknowledgeCapsLock(physicalCapsLock)
    }

    func pressCapsLock(modifiers: KeyModifiers = []) -> Bool {
        physicalCapsLock.toggle()
        let changed = session.handleCapsLock(physicalCapsLock, modifiers: modifiers, host: host)
        synchronizeHardware()
        return changed
    }

    func type(_ text: String, capsLock: Bool? = nil, modifiers: KeyModifiers = [], isRepeat: Bool = false,
              host nextHost: UppercaseHost? = nil) {
        let target = nextHost ?? host
        // Returning false asks the client application to insert its original text.
        if !session.handle(KeyStroke(code: 0, characters: text, modifiers: modifiers, isRepeat: isRepeat, capsLock: capsLock ?? physicalCapsLock), host: target) {
            target.commit(text)
        }
        synchronizeHardware()
    }
}

@MainActor private final class UppercaseProvider: CandidateProviding {
    var delaysResponse = false
    var pendingResponse: CheckedContinuation<[Candidate], any Error>?
    func warm() {}
    func candidates(for pinyin: String, context: String) async throws -> [Candidate] {
        if delaysResponse { return try await withCheckedThrowingContinuation { pendingResponse = $0 } }
        return []
    }
}

@MainActor private final class UppercaseTranslator: CandidateTranslating {
    func translate(_ sources: [String], to language: TranslationLanguage) async throws -> [String] { sources }
}

@MainActor private final class UppercaseSpeaker: SpeechPlaying {
    func speak(_ text: String, language: TranslationLanguage) -> Bool { true }
    func stop() {}
}

@MainActor private final class UppercasePresenter: CandidatePresenting {
    var candidatesVisible = false
    var caseStatuses: [Bool] = []
    var modeStatuses: [InputMode] = []
    func show(_ presentation: CandidatePresentation) { candidatesVisible = true }
    func showLoading(pinyin: String) { candidatesVisible = true }
    func showModeStatus(mode: InputMode) { modeStatuses.append(mode) }
    func showCaseStatus(uppercaseLocked: Bool) { caseStatuses.append(uppercaseLocked) }
    func hide() { candidatesVisible = false }
}

@MainActor private final class UppercaseHost: InputHost {
    var committed: [String] = []
    var markedText = ""
    var onCommit: (() -> Void)?
    func precedingContext() -> String { committed.joined() + markedText }
    func setMarkedText(_ text: String) { markedText = text }
    func commit(_ text: String) {
        committed.append(text)
        markedText = ""
        let callback = onCommit
        onCommit = nil
        callback?()
    }
}
