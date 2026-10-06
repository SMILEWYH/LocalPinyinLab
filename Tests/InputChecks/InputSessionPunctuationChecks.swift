import PinyinCore
import PinyinApplication

@MainActor final class InputSessionPunctuationChecks {
    private let punctuation: [(String, String)] = [
        (",", "，"), (".", "。"), ("?", "？"), ("!", "！"), (":", "："), (";", "；"),
        ("(", "（"), (")", "）"), ("[", "【"), ("]", "】"), ("<", "《"), (">", "》"),
        ("\\", "、"), ("^", "……"), ("_", "——"), ("$", "￥"), ("~", "～")
    ]

    func chinesePunctuation() throws {
        let fixture = PunctuationFixture()
        for (input, expected) in punctuation {
            let previousCount = fixture.host.committed.count
            try checkTrue(fixture.session.handle(KeyStroke(code: 0, characters: input), host: fixture.host))
            try checkEqual(Array(fixture.host.committed.dropFirst(previousCount)), [expected])
            try checkTrue(fixture.session.composition.isEmpty)
        }
    }

    func englishPunctuation() throws {
        let fixture = PunctuationFixture()
        try checkTrue(fixture.session.handleCapsLock(true, host: fixture.host))
        for input in punctuation.map(\.0) + ["\"", "'"] {
            try checkFalse(fixture.session.handle(KeyStroke(code: 0, characters: input, capsLock: true), host: fixture.host))
        }
        try checkTrue(fixture.host.committed.isEmpty)
        try checkTrue(fixture.session.composition.isEmpty)
    }

    func capsLockSwitchesPunctuation() throws {
        let fixture = PunctuationFixture()
        try checkTrue(fixture.session.handle(KeyStroke(code: 43, characters: ","), host: fixture.host))
        try checkTrue(fixture.session.handleCapsLock(true, host: fixture.host))
        try checkFalse(fixture.session.handleCapsLock(true, host: fixture.host))
        try checkFalse(fixture.session.handle(KeyStroke(code: 43, characters: ",", capsLock: true), host: fixture.host))
        try checkEqual(fixture.session.mode, .englishDirect)
        try checkTrue(fixture.session.handleCapsLock(false, host: fixture.host))
        try checkTrue(fixture.session.handle(KeyStroke(code: 43, characters: ","), host: fixture.host))
        try checkEqual(fixture.session.mode, .chinesePinyin)
        try checkEqual(fixture.host.committed, ["，", "，"])
    }

    func shortcutSwitchesPunctuation() throws {
        let fixture = PunctuationFixture()
        let toggle = KeyStroke(code: 49, characters: " ", modifiers: [.control, .shift])
        try checkTrue(fixture.session.handle(toggle, host: fixture.host))
        fixture.session.acknowledgeCapsLock(true)
        try checkTrue(fixture.session.handle(KeyStroke(code: 49, characters: " ", modifiers: [.control, .shift], isRepeat: true, capsLock: true), host: fixture.host))
        try checkFalse(fixture.session.handle(KeyStroke(code: 47, characters: ".", capsLock: true), host: fixture.host))
        try checkEqual(fixture.session.mode, .englishDirect)
        try checkTrue(fixture.session.handle(KeyStroke(code: 49, characters: " ", modifiers: [.control, .shift], capsLock: true), host: fixture.host))
        fixture.session.acknowledgeCapsLock(false)
        try checkTrue(fixture.session.handle(KeyStroke(code: 47, characters: "."), host: fixture.host))
        try checkEqual(fixture.host.committed, ["。"])
    }

    func shortcutsPassThrough() throws {
        let fixture = PunctuationFixture()
        for modifier: KeyModifiers in [.command, .control, .option, [.command, .shift]] {
            for input in [",", ".", "\"", "'"] {
                try checkFalse(fixture.session.handle(KeyStroke(code: 43, characters: input, modifiers: modifier), host: fixture.host))
            }
        }
        try checkTrue(fixture.host.committed.isEmpty)
        try checkTrue(fixture.session.composition.isEmpty)
    }

    func pinyinApostrophe() throws {
        let fixture = PunctuationFixture()
        for input in ["x", "i", "'", "a", "n"] {
            try checkTrue(fixture.session.handle(KeyStroke(code: 0, characters: input), host: fixture.host))
        }
        try checkEqual(fixture.session.composition.pending, "xi'an")
        try checkEqual(fixture.host.markedText, "xi'an")
        try checkTrue(fixture.host.committed.isEmpty)
    }

    func emptyCompositionApostrophe() throws {
        let fixture = PunctuationFixture()
        try checkTrue(fixture.session.handle(KeyStroke(code: 39, characters: "'"), host: fixture.host))
        try checkEqual(fixture.host.committed, ["‘"])
        try checkTrue(fixture.session.composition.isEmpty)
        fixture.host.context += "你好"
        try checkTrue(fixture.session.handle(KeyStroke(code: 39, characters: "'"), host: fixture.host))
        try checkEqual(fixture.host.committed, ["‘", "’"])
    }

    func quotesFollowCursorContext() throws {
        let fixture = PunctuationFixture()
        let cases = [
            ("", "\"", "“"), ("他说：“你好", "\"", "”"),
            ("他说：“你好”。", "\"", "“"), ("引文‘文字", "'", "’"),
            ("引文‘文字’结束", "'", "‘"), ("“外层‘内层’文字", "\"", "”"),
            ("‘外层“内层”文字", "'", "’")
        ]
        for (context, input, expected) in cases {
            fixture.host.context = context
            try checkEqual(ChinesePunctuation.text(for: input, preceding: context), expected)
            try checkTrue(fixture.session.handle(KeyStroke(code: 39, characters: input), host: fixture.host))
            try checkEqual(fixture.host.committed.last, expected)
        }
    }

    func quotesAreIndependentAcrossHosts() throws {
        let fixture = PunctuationFixture()
        let otherHost = RecordingHost()
        try checkTrue(fixture.session.handle(KeyStroke(code: 39, characters: "\""), host: fixture.host))
        try checkTrue(fixture.session.handle(KeyStroke(code: 39, characters: "\""), host: otherHost))
        try checkEqual(fixture.host.committed, ["“"])
        try checkEqual(otherHost.committed, ["“"])
        fixture.host.context += "第一份文档"
        try checkTrue(fixture.session.handle(KeyStroke(code: 39, characters: "\""), host: fixture.host))
        try checkEqual(fixture.host.committed, ["“", "”"])
        try checkEqual(otherHost.committed, ["“"])
    }

    func longMarkedTextPreservesOpeningQuote() throws {
        let fixture = PunctuationFixture()
        fixture.host.context = "“"
        let pinyin = String(repeating: "a", count: 70)
        try checkTrue(fixture.session.handle(KeyStroke(code: 0, characters: pinyin), host: fixture.host))
        try checkEqual(fixture.host.precedingContext(), "“" + pinyin)
        try checkTrue(fixture.session.handle(KeyStroke(code: 39, characters: "\""), host: fixture.host))
        try checkEqual(fixture.host.committed, [pinyin + "”"])
        try checkTrue(fixture.session.composition.isEmpty)
    }

    func contextReentrySwitchesToEnglish() throws {
        let fixture = PunctuationFixture()
        fixture.host.context = "“"
        try checkTrue(fixture.session.handle(KeyStroke(code: 45, characters: "ni"), host: fixture.host))
        var modeChanged = false
        fixture.host.onReadContext = { [weak session = fixture.session, weak host = fixture.host] in
            guard let session, let host else { return }
            modeChanged = session.handleCapsLock(true, host: host)
        }
        try checkFalse(fixture.session.handle(KeyStroke(code: 39, characters: "\""), host: fixture.host))
        try checkTrue(modeChanged)
        try checkEqual(fixture.session.mode, .englishDirect)
        try checkEqual(fixture.host.committed, ["ni"])
        try checkTrue(fixture.session.composition.isEmpty)
    }

    func unmappedTextIsPreserved() throws {
        let fixture = PunctuationFixture()
        for input in ["1", " ", "/", "@", "#", "%", "&", "*", "+", "=", "-", "，", "。", "🙂"] {
            try checkEqual(ChinesePunctuation.text(for: input, preceding: ""), nil)
            try checkFalse(fixture.session.handle(KeyStroke(code: 0, characters: input), host: fixture.host))
        }
        try checkTrue(fixture.host.committed.isEmpty)
    }

    func compositionCommitsWithPunctuation() throws {
        let fixture = PunctuationFixture()
        try checkTrue(fixture.session.handle(KeyStroke(code: 45, characters: "nihao"), host: fixture.host))
        var wasEmptyDuringCommit = false
        fixture.host.onCommit = { [weak session = fixture.session] in
            wasEmptyDuringCommit = session?.composition.isEmpty == true
        }
        try checkTrue(fixture.session.handle(KeyStroke(code: 43, characters: ","), host: fixture.host))
        try checkEqual(fixture.host.committed, ["nihao，"])
        try checkTrue(wasEmptyDuringCommit)
        try checkTrue(fixture.session.composition.isEmpty)
        try checkTrue(fixture.session.candidates.rows.isEmpty)
        try checkFalse(fixture.presenter.isVisible)
    }

    func lateCandidatesCannotReviveComposition() async throws {
        let fixture = PunctuationFixture()
        fixture.provider.delaysResponse = true
        try checkTrue(fixture.session.handle(KeyStroke(code: 45, characters: "ni"), host: fixture.host))
        for _ in 0..<100 where fixture.provider.pendingResponse == nil { await Task.yield() }
        try checkTrue(fixture.provider.pendingResponse != nil)
        try checkTrue(fixture.session.handle(KeyStroke(code: 43, characters: ","), host: fixture.host))
        fixture.provider.pendingResponse?.resume(returning: [Candidate(text: "你", consumedCount: 2)])
        fixture.provider.pendingResponse = nil
        for _ in 0..<100 { await Task.yield() }
        try checkEqual(fixture.host.committed, ["ni，"])
        try checkTrue(fixture.session.composition.isEmpty)
        try checkTrue(fixture.session.candidates.rows.isEmpty)
        try checkFalse(fixture.presenter.isVisible)
    }

    func reentrantHostChange() throws {
        let fixture = PunctuationFixture()
        let otherHost = RecordingHost()
        try checkTrue(fixture.session.handle(KeyStroke(code: 45, characters: "ni"), host: fixture.host))
        var replacementInputHandled = false
        fixture.host.onCommit = { [weak session = fixture.session] in
            replacementInputHandled = session?.handle(KeyStroke(code: 7, characters: "x"), host: otherHost) == true
        }
        try checkTrue(fixture.session.handle(KeyStroke(code: 43, characters: ","), host: fixture.host))
        try checkTrue(replacementInputHandled)
        try checkEqual(fixture.host.committed, ["ni，"])
        try checkTrue(otherHost.committed.isEmpty)
        try checkEqual(otherHost.markedText, "x")
        try checkEqual(fixture.session.composition.pending, "x")
    }
}

@MainActor private final class PunctuationFixture {
    let provider = StubCandidateProvider()
    let host = RecordingHost()
    let presenter = StubPresenter()
    let session: InputSession

    init() {
        session = InputSession(provider: provider, translator: StubTranslator(), speaker: StubSpeaker(), presenter: presenter)
        session.activate(capsLock: false)
    }
}

@MainActor private final class StubCandidateProvider: CandidateProviding {
    var delaysResponse = false
    var pendingResponse: CheckedContinuation<[Candidate], any Error>?
    func warm() {}
    func candidates(for pinyin: String, context: String) async throws -> [Candidate] {
        if delaysResponse {
            return try await withCheckedThrowingContinuation { pendingResponse = $0 }
        }
        return []
    }
}

@MainActor private final class StubTranslator: CandidateTranslating {
    func translate(_ sources: [String]) async throws -> [String] { sources }
}

@MainActor private final class StubSpeaker: SpeechPlaying {
    func speak(_ text: String) -> Bool { true }
    func stop() {}
}

@MainActor private final class StubPresenter: CandidatePresenting {
    var isVisible = false
    func show(_ presentation: CandidatePresentation) { isVisible = true }
    func showLoading(pinyin: String) { isVisible = true }
    func showModeStatus(mode: InputMode) { isVisible = true }
    func showCaseStatus(uppercaseLocked: Bool) { isVisible = true }
    func hide() { isVisible = false }
}

@MainActor private final class RecordingHost: InputHost {
    var context = ""
    var committed: [String] = []
    var markedText = ""
    var onCommit: (() -> Void)?
    var onReadContext: (() -> Void)?
    func precedingContext() -> String {
        // IMK's text before the insertion point already includes marked text.
        let text = context + markedText
        onReadContext?()
        return text
    }
    func setMarkedText(_ text: String) { markedText = text }
    func commit(_ text: String) {
        committed.append(text)
        context += text
        markedText = ""
        onCommit?()
    }
}
