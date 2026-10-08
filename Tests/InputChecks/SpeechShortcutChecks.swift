import Foundation
import PinyinCore
import PinyinApplication

@MainActor final class SpeechShortcutChecks {
    func validatesTwoAndThreeKeys() throws {
        try checkEqual(SpeechShortcut.default.displayName, "Command + Option")
        try checkTrue(SpeechShortcut.default.isModifierOnly)
        for modifiers: KeyModifiers in [[.command, .option], [.control, .shift, .option]] {
            try checkTrue(SpeechShortcut(modifiers: modifiers) != nil)
        }
        for modifiers: KeyModifiers in [.control, [.control, .shift]] {
            try checkTrue(SpeechShortcut(modifiers: modifiers, keyCode: 35) != nil)
        }
        try checkEqual(SpeechShortcut(modifiers: [.shift], keyCode: 48)?.displayName, "Shift + Tab")
        try checkEqual(SpeechShortcut(modifiers: [.control, .shift], keyCode: 15)?.displayName, "Control + Shift + R")
        for modifiers: KeyModifiers in [[], .command, [.control, .shift, .command, .option], KeyModifiers(rawValue: -1)] {
            try checkTrue(SpeechShortcut(modifiers: modifiers) == nil)
        }
        try checkTrue(SpeechShortcut(modifiers: [], keyCode: 35) == nil)
        try checkTrue(SpeechShortcut(modifiers: [.control, .shift, .command], keyCode: 35) == nil)
        try checkTrue(SpeechShortcut(modifiers: [.command], keyCode: 65_535) == nil)
        try checkEqual(SpeechShortcut(modifiers: [.control, .shift], keyCode: 49)?.displayName, "Control + Shift + Space")
        try checkTrue(SpeechShortcut(modifiers: [.shift], keyCode: 123) == nil)
        try checkTrue(SpeechShortcut(modifiers: [.shift], keyCode: 49) == nil)
        try checkTrue(SpeechShortcut(modifiers: [.shift], keyCode: 18) == nil)
        try checkEqual(Set(SpeechShortcut.keyOptions.map(\.code)).count, SpeechShortcut.keyOptions.count)
    }

    func validatesPersistedValues() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for shortcut in [SpeechShortcut.default,
                         SpeechShortcut(modifiers: [.control, .shift], keyCode: 15)!,
                         SpeechShortcut(modifiers: [.control, .shift], keyCode: 49)!] {
            try checkEqual(try decoder.decode(SpeechShortcut.self, from: encoder.encode(shortcut)), shortcut)
        }
        let invalid = [
            #"{"modifiers":0}"#, #"{"modifiers":8}"#, #"{"modifiers":15}"#,
            #"{"modifiers":-1,"keyCode":35}"#, #"{"modifiers":16,"keyCode":35}"#,
            #"{"modifiers":8,"keyCode":65535}"#, #"{"modifiers":8,"keyCode":-1}"#,
            #"{"modifiers":1,"keyCode":123}"#,
            #"{"modifiers":8,"keyCode":"P"}"#, #"{}"#
        ]
        for json in invalid {
            let decoded = try? decoder.decode(SpeechShortcut.self, from: Data(json.utf8))
            try checkTrue(decoded == nil)
        }
        let extraName = Data(#"{"modifiers":12,"displayName":"Untrusted name"}"#.utf8)
        try checkEqual(try decoder.decode(SpeechShortcut.self, from: extraName).displayName, "Command + Option")
    }

    func defaultGestureSpeaksOnceAfterRelease() async throws {
        let fixture = SpeechFixture()
        defer { fixture.finish() }
        try await fixture.prepare()
        try checkFalse(fixture.flags([.command]))
        try checkTrue(fixture.session.isSpeechShortcutGestureInProgress)
        try checkFalse(fixture.flags([.command, .option]))
        try checkFalse(fixture.flags([.command, .option]))
        try checkTrue(fixture.speaker.calls.isEmpty)
        try checkFalse(fixture.flags([.option]))
        try checkTrue(fixture.speaker.calls.isEmpty)
        try checkTrue(fixture.flags([]))
        try checkEqual(fixture.speaker.calls, ["en:词1"])
        try checkFalse(fixture.flags([]))
        try checkEqual(fixture.speaker.calls.count, 1)
        try checkFalse(fixture.session.isSpeechShortcutGestureInProgress)
        try checkFalse(fixture.flags([.option]))
        try checkFalse(fixture.flags([.command, .option]))
        try checkTrue(fixture.flags([]))
        try checkEqual(fixture.speaker.calls.count, 2)
    }

    func threeModifierGestureRequiresTheCompleteChord() async throws {
        let fixture = SpeechFixture(shortcut: SpeechShortcut(modifiers: [.control, .shift, .option])!)
        defer { fixture.finish() }
        try await fixture.prepare()
        _ = fixture.flags([.control])
        _ = fixture.flags([.control, .shift])
        try checkFalse(fixture.flags([]))
        try checkTrue(fixture.speaker.calls.isEmpty)
        _ = fixture.flags([.option])
        _ = fixture.flags([.option, .shift])
        _ = fixture.flags([.option, .shift, .control])
        _ = fixture.flags([.option, .control])
        _ = fixture.flags([.control])
        try checkTrue(fixture.flags([]))
        try checkEqual(fixture.speaker.calls.count, 1)
    }

    func otherKeysAndExtraModifiersCancelTheWholeGesture() async throws {
        let fixture = SpeechFixture()
        defer { fixture.finish() }
        try await fixture.prepare()
        _ = fixture.flags([.command])
        _ = fixture.flags([.command, .option])
        // A normal application shortcut must never play on its modifier release.
        try checkFalse(fixture.press(35, "p", modifiers: [.command, .option]))
        _ = fixture.flags([.option])
        _ = fixture.flags([.command, .option])
        try checkFalse(fixture.flags([]))
        try checkTrue(fixture.speaker.calls.isEmpty)

        _ = fixture.flags([.command])
        _ = fixture.flags([.command, .option])
        _ = fixture.flags([.command, .option, .shift])
        _ = fixture.flags([.command, .option])
        try checkFalse(fixture.flags([]))
        try checkTrue(fixture.speaker.calls.isEmpty)
        try checkTrue(fixture.defaultChord())
    }

    func releasingAndRepressingModifiersCannotRearm() async throws {
        let fixture = SpeechFixture()
        defer { fixture.finish() }
        try await fixture.prepare()
        _ = fixture.flags([.command])
        _ = fixture.flags([.command, .option])
        _ = fixture.flags([.command])
        _ = fixture.flags([.command, .option])
        try checkFalse(fixture.flags([]))
        try checkTrue(fixture.speaker.calls.isEmpty)
        try checkTrue(fixture.defaultChord())
        fixture.session.setSpeechShortcut(SpeechShortcut(modifiers: [.command, .option, .control])!)
        _ = fixture.flags([.command])
        _ = fixture.flags([.command, .option])
        _ = fixture.flags([.command])
        _ = fixture.flags([.command, .option, .control])
        try checkFalse(fixture.flags([]))
        try checkEqual(fixture.speaker.calls.count, 1)
    }

    func aTranslationArrivingDuringTheChordDoesNotArmIt() async throws {
        let fixture = SpeechFixture()
        defer { fixture.finish() }
        fixture.translator.deferred = true
        try checkTrue(fixture.press(45, "ni"))
        try await fixture.wait { fixture.translator.pending != nil }
        try checkEqual(fixture.session.queryState, .ready)
        _ = fixture.flags([.command])
        _ = fixture.flags([.command, .option])
        fixture.translator.complete()
        try await fixture.wait { fixture.session.candidates.selectedRow?.speechText != nil }
        _ = fixture.flags([.command, .option])
        try checkFalse(fixture.flags([]))
        try checkTrue(fixture.speaker.calls.isEmpty)
        try checkTrue(fixture.defaultChord())
    }

    func customKeyChordsRequireReadySpeechAndDoNotRepeat() async throws {
        let shortcut = SpeechShortcut(modifiers: [.command], keyCode: 35)!
        let fixture = SpeechFixture(shortcut: shortcut)
        defer { fixture.finish() }
        try checkFalse(fixture.press(35, "p", modifiers: [.command]))
        fixture.translator.deferred = true
        try checkTrue(fixture.press(45, "ni"))
        try checkFalse(fixture.press(35, "p", modifiers: [.command]))
        try await fixture.wait { fixture.translator.pending != nil }
        try checkFalse(fixture.press(35, "p", modifiers: [.command]))
        fixture.translator.complete()
        try await fixture.wait { fixture.session.candidates.selectedRow?.speechText != nil }
        try checkFalse(fixture.press(35, "p", modifiers: [.command, .shift]))
        try checkTrue(fixture.press(35, "p", modifiers: [.command]))
        try checkTrue(fixture.press(35, "p", modifiers: [.command], isRepeat: true))
        try checkEqual(fixture.speaker.calls.count, 1)
        try checkEqual(fixture.session.composition.pending, "ni")
        try checkTrue(fixture.host.committed.isEmpty)

        fixture.session.setSpeechShortcut(SpeechShortcut(modifiers: [.control, .shift], keyCode: 49)!)
        try checkFalse(fixture.press(35, "p", modifiers: [.command]))
        try checkTrue(fixture.press(49, " ", modifiers: [.control, .shift]))
        try checkTrue(fixture.press(49, " ", modifiers: [.control, .shift], isRepeat: true))
        try checkEqual(fixture.speaker.calls.count, 2)
        try checkEqual(fixture.session.mode, .chinesePinyin)
        try checkEqual(fixture.session.composition.pending, "ni")
        try checkTrue(fixture.host.committed.isEmpty)
        fixture.session.setSpeechShortcut(SpeechShortcut(modifiers: [.shift], keyCode: 48)!)
        try checkTrue(fixture.press(48, "\t", modifiers: [.shift]))
        try checkEqual(fixture.speaker.calls.count, 3)
        try checkEqual(fixture.session.composition.pending, "ni")
        _ = fixture.session.handleCapsLock(true, host: fixture.host)
        try checkFalse(fixture.press(48, "\t", modifiers: [.shift], capsLock: true))
        try checkEqual(fixture.speaker.calls.count, 3)
    }

    func explicitCancellationAndConfigurationChangesNeedFreshChords() async throws {
        let fixture = SpeechFixture()
        defer { fixture.finish() }
        try await fixture.prepare()
        // A mouse/key event can invalidate the chord before IMK observes its
        // first modifier. The stale empty baseline must not permit arming.
        fixture.session.cancelSpeechShortcutGesture()
        _ = fixture.flags([.command])
        _ = fixture.flags([.command, .option])
        try checkFalse(fixture.flags([]))
        try checkTrue(fixture.speaker.calls.isEmpty)
        _ = fixture.flags([.command, .option])
        fixture.session.cancelSpeechShortcutGesture()
        _ = fixture.flags([.option])
        _ = fixture.flags([.command, .option])
        try checkFalse(fixture.flags([]))
        try checkTrue(fixture.speaker.calls.isEmpty)
        try checkTrue(fixture.defaultChord())

        _ = fixture.flags([.command, .option])
        fixture.session.setSpeechShortcut(SpeechShortcut(modifiers: [.control, .shift])!)
        fixture.session.setSpeechShortcut(.default)
        try checkFalse(fixture.flags([]))
        try checkEqual(fixture.speaker.calls.count, 1)
        try checkTrue(fixture.defaultChord())
        _ = fixture.flags([.command, .option])
        fixture.session.setSpeechShortcut(.default)
        try checkTrue(fixture.flags([]))
        try checkEqual(fixture.speaker.calls.count, 3)
    }

    func candidateLanguageAndLifecycleChangesCancelGestures() async throws {
        let fixture = SpeechFixture()
        defer { fixture.finish() }
        try await fixture.prepare()
        _ = fixture.flags([.command, .option])
        try checkTrue(fixture.press(125))
        try checkFalse(fixture.flags([]))
        try checkTrue(fixture.speaker.calls.isEmpty)
        try checkTrue(fixture.defaultChord())
        try checkEqual(fixture.speaker.calls, ["en:词2"])

        _ = fixture.flags([.command, .option])
        fixture.session.setTranslationLanguage(.japanese)
        try await fixture.wait { fixture.session.candidates.selectedRow?.speechText == "ja:词2" }
        try checkFalse(fixture.flags([]))
        try checkEqual(fixture.speaker.calls.count, 1)
        try checkTrue(fixture.defaultChord())
        try checkEqual(fixture.speaker.calls.last, "ja:词2")

        _ = fixture.flags([.command, .option])
        fixture.session.deactivate()
        fixture.session.activate(capsLock: false)
        try checkFalse(fixture.flags([]))
        try checkEqual(fixture.speaker.calls.count, 2)
        try await fixture.prepare()
        _ = fixture.flags([.command, .option])
        let anotherHost = SpeechHost()
        try checkFalse(fixture.session.handleSpeechModifiers([], host: anotherHost))
        try checkEqual(fixture.speaker.calls.count, 2)
        try checkTrue(anotherHost.committed.isEmpty)
    }
}

@MainActor private final class SpeechFixture {
    let speaker = ShortcutSpeaker()
    let translator = ShortcutTranslator()
    let host = SpeechHost()
    let session: InputSession

    init(shortcut: SpeechShortcut = .default) {
        session = InputSession(provider: ShortcutProvider(), translator: translator, speaker: speaker,
                               presenter: ShortcutPresenter(), speechShortcut: shortcut)
        session.activate(capsLock: false)
    }

    func press(_ code: UInt16, _ text: String = "", modifiers: KeyModifiers = [], isRepeat: Bool = false, capsLock: Bool = false) -> Bool {
        session.handle(KeyStroke(code: code, characters: text, modifiers: modifiers, isRepeat: isRepeat, capsLock: capsLock), host: host)
    }
    func flags(_ modifiers: KeyModifiers) -> Bool { session.handleSpeechModifiers(modifiers, host: host) }
    func defaultChord() -> Bool {
        _ = flags([.command])
        _ = flags([.command, .option])
        return flags([])
    }
    func prepare() async throws {
        try checkTrue(press(45, "ni"))
        try await wait { self.session.candidates.selectedRow?.speechText != nil }
    }
    func wait(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !predicate() { await Task.yield() }
        try checkTrue(predicate())
    }
    func finish() { session.cancel(); translator.complete() }
}

@MainActor private final class ShortcutProvider: CandidateProviding {
    func warm() {}
    func candidates(for pinyin: String, context: String) async throws -> [Candidate] {
        [Candidate(text: "词1", consumedCount: pinyin.count), Candidate(text: "词2", consumedCount: pinyin.count)]
    }
}

@MainActor private final class ShortcutTranslator: CandidateTranslating {
    var deferred = false
    var pending: CheckedContinuation<[String], any Error>?
    private var response: [String] = []
    func translate(_ sources: [String], to language: TranslationLanguage) async throws -> [String] {
        let response = sources.map { "\(language.rawValue):\($0)" }
        self.response = response
        if deferred { return try await withCheckedThrowingContinuation { pending = $0 } }
        return response
    }
    func complete() {
        pending?.resume(returning: response)
        pending = nil
    }
}

@MainActor private final class ShortcutSpeaker: SpeechPlaying {
    var calls: [String] = []
    func speak(_ text: String, language: TranslationLanguage) -> Bool { calls.append(text); return true }
    func stop() {}
}

@MainActor private final class SpeechHost: InputHost {
    var committed: [String] = []
    func precedingContext() -> String { "" }
    func setMarkedText(_ text: String) {}
    func commit(_ text: String) { committed.append(text) }
}

@MainActor private final class ShortcutPresenter: CandidatePresenting {
    func show(_ presentation: CandidatePresentation) {}
    func showLoading(pinyin: String) {}
    func showModeStatus(mode: InputMode) {}
    func showCaseStatus(uppercaseLocked: Bool) {}
    func hide() {}
}
