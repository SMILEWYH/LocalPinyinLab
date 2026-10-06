import PinyinCore
import PinyinApplication

@MainActor final class UppercaseChecks {
    func togglesFromBothModesAndCapsStates() throws {
        for capsLock in [false, true] {
            for startsInEnglish in [false, true] {
                let fixture = UppercaseFixture(capsLock: capsLock)
                if startsInEnglish { try fixture.switchMode(capsLock: capsLock) }
                try checkTrue(fixture.session.handleCapsLock(!capsLock, modifiers: .shift, host: fixture.host))
                try checkEqual(fixture.session.mode, .englishDirect)
                try checkTrue(fixture.session.isUppercaseLocked)
                try checkTrue(fixture.session.handleCapsLock(capsLock, modifiers: .shift, host: fixture.host))
                try checkEqual(fixture.session.mode, .englishDirect)
                try checkFalse(fixture.session.isUppercaseLocked)
                try checkEqual(fixture.presenter.caseStatuses, [true, false])
                try checkTrue(fixture.host.committed.isEmpty)
                try checkTrue(fixture.host.markedText.isEmpty)
            }
        }
    }

    func repeatedEventsDoNotToggleOrRepeatStatus() throws {
        for capsLock in [false, true] {
            let fixture = UppercaseFixture(capsLock: capsLock)
            try checkTrue(fixture.session.handleCapsLock(!capsLock, modifiers: .shift, host: fixture.host))
            try checkFalse(fixture.session.handleCapsLock(!capsLock, modifiers: .shift, host: fixture.host))
            try checkFalse(fixture.session.handleCapsLock(!capsLock, host: fixture.host))
            try checkTrue(fixture.host.committed.isEmpty)
            fixture.type(capsLock ? "a" : "A", capsLock: !capsLock)
            fixture.type(capsLock ? "b" : "B", capsLock: !capsLock, isRepeat: true)
            try checkEqual(fixture.host.committed, ["A", "B"])
            try checkTrue(fixture.session.isUppercaseLocked)
            try checkEqual(fixture.session.mode, .englishDirect)
            try checkEqual(fixture.presenter.caseStatuses, [true])
        }
    }

    func uppercaseSurvivesHostAndSessionChanges() throws {
        let state = InputModeState()
        let fixture = UppercaseFixture(state: state)
        try checkTrue(fixture.session.handleCapsLock(true, modifiers: .shift, host: fixture.host))
        fixture.type("A", capsLock: true)
        let nextHost = UppercaseHost()
        fixture.type("B", capsLock: true, host: nextHost)
        fixture.session.deactivate()
        fixture.session.activate(capsLock: false)
        fixture.type("c", capsLock: false)
        let nextSession = UppercaseFixture(capsLock: false, state: state)
        nextSession.type("d", capsLock: false)
        try checkEqual(fixture.host.committed, ["A", "C"])
        try checkEqual(nextHost.committed, ["B"])
        try checkEqual(nextSession.host.committed, ["D"])
        try checkTrue(nextSession.session.isUppercaseLocked)
        try checkEqual(nextSession.session.mode, .englishDirect)
        try checkEqual(fixture.presenter.caseStatuses, [true])
        try checkTrue(nextSession.presenter.caseStatuses.isEmpty)
    }

    func keyDownRecoversMissedCapsEvent() throws {
        for capsLock in [false, true] {
            let fixture = UppercaseFixture(capsLock: capsLock)
            fixture.type("N", capsLock: !capsLock, modifiers: .shift)
            try checkFalse(fixture.session.handleCapsLock(!capsLock, modifiers: .shift, host: fixture.host))
            try checkEqual(fixture.session.mode, .englishDirect)
            try checkTrue(fixture.session.isUppercaseLocked)
            try checkEqual(fixture.host.committed, ["N"])
            try checkEqual(fixture.presenter.caseStatuses, [true])
        }
    }

    func returningToChineseClearsUppercase() throws {
        for usesCapsLock in [false, true] {
            let fixture = UppercaseFixture()
            try checkTrue(fixture.session.handleCapsLock(true, modifiers: .shift, host: fixture.host))
            if usesCapsLock {
                try checkTrue(fixture.session.handleCapsLock(false, host: fixture.host))
            } else {
                try fixture.switchMode(capsLock: true)
            }
            try checkEqual(fixture.session.mode, .chinesePinyin)
            try checkFalse(fixture.session.isUppercaseLocked)
            let physicalCaps = !usesCapsLock
            try fixture.switchMode(capsLock: physicalCaps)
            fixture.type(physicalCaps ? "A" : "a", capsLock: physicalCaps)
            try checkEqual(fixture.host.committed, ["a"])
            try checkEqual(fixture.session.mode, .englishDirect)
            try checkFalse(fixture.session.isUppercaseLocked)
        }
    }

    func onlyLettersChangeAndShortcutsPassThrough() throws {
        let fixture = UppercaseFixture(capsLock: true)
        try checkTrue(fixture.session.handleCapsLock(false, modifiers: .shift, host: fixture.host))
        fixture.type("a", capsLock: false)
        fixture.type("z", capsLock: false)
        fixture.type("B", capsLock: false, modifiers: .shift)
        try checkEqual(fixture.host.committed, ["A", "Z", "B"])
        let unchanged = ["1", " ", ",", ".", "!", "@", "'", "\"", "é", "中", "🙂"]
        for text in unchanged {
            try checkFalse(fixture.session.handle(KeyStroke(code: 0, characters: text), host: fixture.host))
        }
        for modifiers: KeyModifiers in [.command, .control, .option, [.command, .shift], [.control, .shift], [.option, .shift]] {
            try checkFalse(fixture.session.handle(KeyStroke(code: 0, characters: "a", modifiers: modifiers), host: fixture.host))
        }
        try checkEqual(fixture.host.committed, ["A", "Z", "B"])
        try checkTrue(fixture.session.composition.isEmpty)
        try checkEqual(fixture.presenter.caseStatuses, [true])
        try checkTrue(fixture.session.handleCapsLock(true, modifiers: .shift, host: fixture.host))
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
        try checkTrue(fixture.session.handleCapsLock(true, modifiers: .shift, host: fixture.host))
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
                    _ = fixture.session.handle(KeyStroke(code: 49, characters: " ", modifiers: [.control, .shift], capsLock: true), host: fixture.host)
                case 1:
                    fixture.session.cancel()
                default:
                    _ = fixture.session.handle(KeyStroke(code: 0, capsLock: true), host: UppercaseHost())
                    _ = fixture.session.handle(KeyStroke(code: 0, capsLock: true), host: fixture.host)
                }
            }
            try checkTrue(fixture.session.handleCapsLock(true, modifiers: .shift, host: fixture.host))
            try checkEqual(fixture.host.committed, ["ni"])
            try checkTrue(fixture.presenter.caseStatuses.isEmpty)
        }
    }
}

@MainActor private final class UppercaseFixture {
    let provider = UppercaseProvider()
    let host = UppercaseHost()
    let presenter = UppercasePresenter()
    let session: InputSession

    init(capsLock: Bool = false, state: InputModeState = InputModeState()) {
        session = InputSession(provider: provider, translator: UppercaseTranslator(), speaker: UppercaseSpeaker(),
                               presenter: presenter, modeState: state)
        session.activate(capsLock: capsLock)
    }

    func switchMode(capsLock: Bool) throws {
        try checkTrue(session.handle(KeyStroke(code: 49, characters: " ", modifiers: [.control, .shift], capsLock: capsLock), host: host))
    }

    func type(_ text: String, capsLock: Bool, modifiers: KeyModifiers = [], isRepeat: Bool = false,
              host nextHost: UppercaseHost? = nil) {
        let target = nextHost ?? host
        // Returning false asks the client application to insert its original text.
        if !session.handle(KeyStroke(code: 0, characters: text, modifiers: modifiers, isRepeat: isRepeat, capsLock: capsLock), host: target) {
            target.commit(text)
        }
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
    func translate(_ sources: [String]) async throws -> [String] { sources }
}

@MainActor private final class UppercaseSpeaker: SpeechPlaying {
    func speak(_ text: String) -> Bool { true }
    func stop() {}
}

@MainActor private final class UppercasePresenter: CandidatePresenting {
    var candidatesVisible = false
    var caseStatuses: [Bool] = []
    func show(_ presentation: CandidatePresentation) { candidatesVisible = true }
    func showLoading(pinyin: String) { candidatesVisible = true }
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
