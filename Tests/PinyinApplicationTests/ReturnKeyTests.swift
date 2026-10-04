// Migrates the original Return-key cases to real protocol boundaries, with no source rewriting.
import Foundation
import PinyinCore
import PinyinApplication
import TestSupport

@MainActor private final class Host: InputHost {
    var inserted: [String] = []
    var marked = ""
    var context = "前文"
    var onMark: (() -> Void)?
    var onCommit: (() -> Void)?
    func precedingContext() -> String { context }
    func setMarkedText(_ text: String) { marked = text; onMark?() }
    func commit(_ text: String) { inserted.append(text); marked = ""; onCommit?() }
}

@MainActor private final class Provider: CandidateProviding {
    struct Request {
        let pinyin: String
        let context: String
        let completion: CheckedContinuation<[Candidate], Error>
    }
    var requests: [Request] = []
    func warm() {}
    func candidates(for pinyin: String, context: String) async throws -> [Candidate] {
        try await withCheckedThrowingContinuation { requests.append(Request(pinyin: pinyin, context: context, completion: $0)) }
    }
    func complete(_ rows: [Candidate], at index: Int = 0) { requests.remove(at: index).completion.resume(returning: rows) }
    func fail() { requests.removeFirst().completion.resume(throwing: TranslationFailure.invalidResponse) }
}

@MainActor private final class Translator: CandidateTranslating {
    var requests: [(sources: [String], completion: CheckedContinuation<[String], Error>)] = []
    func translate(_ sources: [String]) async throws -> [String] {
        try await withCheckedThrowingContinuation { requests.append((sources, $0)) }
    }
    func complete(_ text: [String], at index: Int = 0) { requests.remove(at: index).completion.resume(returning: text) }
}

@MainActor private final class Presenter: CandidatePresenting {
    var visible = false
    var shows = 0
    var last: CandidatePresentation?
    func show(_ presentation: CandidatePresentation) { visible = true; shows += 1; last = presentation }
    func showLoading(pinyin: String) {}
    func hide() { visible = false }
}

@MainActor private final class Speaker: SpeechPlaying {
    var spoken: [String] = []
    var stops = 0
    func speak(_ text: String) -> Bool { spoken.append(text); return true }
    func stop() { stops += 1 }
}

@MainActor private final class Fixture {
    let host = Host(), provider = Provider(), translator = Translator(), presenter = Presenter(), speaker = Speaker()
    let modeState: InputModeState
    init(modeState: InputModeState = InputModeState()) { self.modeState = modeState }
    lazy var session = InputSession(provider: provider, translator: translator, speaker: speaker, presenter: presenter, modeState: modeState)
    @discardableResult func key(_ code: UInt16, _ text: String = "", flags: KeyModifiers = [], repeatKey: Bool = false, capsLock: Bool = false) -> Bool {
        session.handle(KeyStroke(code: code, characters: text, modifiers: flags, isRepeat: repeatKey, capsLock: capsLock), host: host)
    }
    func type(_ text: String, capsLock: Bool = false) async throws {
        XCTAssertTrue(key(0, text, capsLock: capsLock))
        try await until { !self.provider.requests.isEmpty }
    }
    func resolve(_ rows: [Candidate]) async throws {
        provider.complete(rows)
        try await until { self.presenter.visible }
    }
    func drain() async throws {
        session.deactivate()
        for _ in 0..<5 {
            while !provider.requests.isEmpty { provider.complete([]) }
            while !translator.requests.isEmpty { translator.complete([]) }
            try await settle()
        }
    }
}

@MainActor private func until(_ condition: () -> Bool) async throws {
    for _ in 0..<400 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(2))
    }
    fatalError("Timed out waiting for controlled asynchronous step")
}
private func settle() async throws { try await Task.sleep(for: .milliseconds(10)) }

@main struct InputSessionTests {
    @MainActor static func main() async throws {
        try await returnsAndLateResponses()
        try await queuedSelectionAndErrors()
        try await obsoleteQueriesAndPageTranslations()
        try await lifecycleModeAndSpeech()
        try await cancellationReentryAndInvalidCandidates()
        try await emojiFilteringKeepsSelectionAndFallbackCorrect()
        try await capsLockEdgesAndEnglishCase()
        try await capsLockAndShortcutShareOneMode()
        try await capsLockCommitsAndRejectsLateResponses()
        try await capsLockStateSurvivesActivationAndIsShared()
        try await capsLockCommitReentry()
        try await mouseCommitAndDeactivatePreserveReentrantInput()
        try await hostChangeDoesNotMoveReentrantComposition()
        print("PASS: Return, queued selection, query/page races, speech, host lifecycle, emoji filtering and Caps Lock mode regression cases")
    }

    @MainActor static func capsLockEdgesAndEnglishCase() async throws {
        let f = Fixture()
        f.session.activate(capsLock: false)
        XCTAssertEqual(f.session.mode, .chinesePinyin)
        XCTAssertFalse(f.session.handleCapsLock(false, host: f.host))
        XCTAssertTrue(f.session.handleCapsLock(true, host: f.host))
        XCTAssertEqual(f.session.mode, .englishDirect)
        XCTAssertFalse(f.session.handleCapsLock(true, host: f.host), "Repeated modifier events must not toggle again")
        XCTAssertTrue(f.key(0, "A", capsLock: true))
        XCTAssertEqual(f.host.inserted, ["a"])
        XCTAssertEqual(f.session.mode, .englishDirect, "The following keyDown repeats the Caps state, not the mode switch")
        XCTAssertTrue(f.key(11, "b", flags: [.shift], capsLock: true))
        XCTAssertEqual(f.host.inserted, ["a", "B"])
        XCTAssertFalse(f.key(8, "C", flags: [.shift], capsLock: true), "Already-correct Shift text should pass through")
        let shortcuts: [KeyModifiers] = [[.command], [.control], [.option], [.command, .shift]]
        for flags in shortcuts {
            XCTAssertFalse(f.key(0, "A", flags: flags, capsLock: true))
        }
        XCTAssertFalse(f.key(0, "É", capsLock: true), "Do not rewrite non-ASCII keyboard-layout output")
        XCTAssertFalse(f.key(19, "@", flags: [.shift], capsLock: true))
        XCTAssertFalse(f.key(36, "\r", capsLock: true))
        XCTAssertEqual(f.host.inserted, ["a", "B"])
        XCTAssertTrue(f.provider.requests.isEmpty)
        XCTAssertTrue(f.session.handleCapsLock(false, host: f.host))
        XCTAssertEqual(f.session.mode, .chinesePinyin)
        XCTAssertFalse(f.session.handleCapsLock(false, host: f.host))
        try await f.drain()

        let missingFlags = Fixture()
        missingFlags.session.activate(capsLock: false)
        XCTAssertTrue(missingFlags.key(0, "A", capsLock: true))
        XCTAssertEqual(missingFlags.session.mode, .englishDirect)
        XCTAssertEqual(missingFlags.host.inserted, ["a"], "keyDown can recover a missed flagsChanged event")
        try await missingFlags.drain()
    }

    @MainActor static func mouseCommitAndDeactivatePreserveReentrantInput() async throws {
        for deactivating in [false, true] {
            let f = Fixture()
            try await f.type("nihao")
            f.host.onCommit = { [weak f] in
                guard let f else { return }
                XCTAssertTrue(f.key(0, "n"))
            }
            if deactivating { f.session.deactivate() } else { f.session.finishComposition() }
            XCTAssertEqual(f.host.inserted, ["nihao"])
            XCTAssertEqual(f.host.marked, "n")
            XCTAssertEqual(f.session.composition.pending, "n", "Host reentry must not lose the new composition after submission")
            f.host.onCommit = nil
            try await f.drain()
        }
    }

    @MainActor static func hostChangeDoesNotMoveReentrantComposition() async throws {
        for capsEvent in [false, true] {
            let f = Fixture(), next = Host(), reentrant = Host()
            f.session.activate(capsLock: false)
            try await f.type("ni")
            f.host.onCommit = { [weak f] in
                guard let f else { return }
                XCTAssertTrue(f.session.handle(KeyStroke(code: 0, characters: "hao"), host: reentrant))
            }
            if capsEvent {
                XCTAssertFalse(f.session.handleCapsLock(true, host: next))
            } else {
                XCTAssertFalse(f.session.handle(KeyStroke(code: 0, characters: "x"), host: next))
            }
            XCTAssertEqual(f.host.inserted, ["ni"])
            XCTAssertEqual(reentrant.marked, "hao")
            XCTAssertEqual(next.marked, "")
            XCTAssertTrue(next.inserted.isEmpty)
            XCTAssertEqual(f.session.composition.pending, "hao")
            XCTAssertEqual(f.session.mode, .chinesePinyin)
            f.host.onCommit = nil
            try await f.drain()
        }
    }

    @MainActor static func capsLockAndShortcutShareOneMode() async throws {
        let f = Fixture()
        f.session.activate(capsLock: false)
        XCTAssertTrue(f.session.handleCapsLock(true, host: f.host))
        XCTAssertTrue(f.key(49, " ", flags: [.control, .shift], capsLock: true))
        XCTAssertEqual(f.session.mode, .chinesePinyin)
        XCTAssertTrue(f.key(49, " ", flags: [.control, .shift], repeatKey: true, capsLock: true))
        XCTAssertEqual(f.session.mode, .chinesePinyin, "Holding the shortcut must not repeatedly toggle modes")
        try await f.type("NI", capsLock: true)
        XCTAssertEqual(f.host.marked, "ni", "A shortcut can select Chinese while physical Caps Lock is still on")
        XCTAssertTrue(f.session.handleCapsLock(false, host: f.host))
        XCTAssertEqual(f.session.mode, .englishDirect)
        XCTAssertEqual(f.host.inserted, ["ni"])
        XCTAssertFalse(f.key(0, "a"))
        XCTAssertTrue(f.session.handleCapsLock(true, host: f.host))
        XCTAssertEqual(f.session.mode, .chinesePinyin)
        XCTAssertTrue(f.key(0, "HAO", capsLock: true))
        XCTAssertEqual(f.host.marked, "hao")
        try await f.drain()
    }

    @MainActor static func capsLockCommitsAndRejectsLateResponses() async throws {
        let pending = Fixture()
        pending.session.activate(capsLock: false)
        try await pending.type("nihao")
        XCTAssertTrue(pending.session.handleCapsLock(true, host: pending.host))
        XCTAssertEqual(pending.host.inserted, ["nihao"])
        XCTAssertEqual(pending.host.marked, "")
        XCTAssertTrue(pending.session.composition.isEmpty)
        pending.provider.complete([Candidate(text: "你好", consumedCount: 5)])
        try await settle()
        XCTAssertFalse(pending.presenter.visible)
        XCTAssertEqual(pending.presenter.shows, 0)
        XCTAssertTrue(pending.translator.requests.isEmpty)
        try await pending.drain()

        let partial = Fixture()
        partial.session.activate(capsLock: false)
        try await partial.type("pingying")
        try await partial.resolve([Candidate(text: "瓶", consumedCount: 4)])
        try await until { !partial.translator.requests.isEmpty }
        XCTAssertTrue(partial.key(49, " "))
        XCTAssertEqual(partial.host.marked, "瓶ying")
        try await until { !partial.provider.requests.isEmpty }
        let shows = partial.presenter.shows
        XCTAssertTrue(partial.session.handleCapsLock(true, host: partial.host))
        XCTAssertEqual(partial.host.inserted, ["瓶ying"])
        XCTAssertEqual(partial.session.mode, .englishDirect)
        partial.provider.complete([Candidate(text: "赢", consumedCount: 4)])
        partial.translator.complete(["Bottle"])
        try await settle()
        XCTAssertFalse(partial.presenter.visible)
        XCTAssertEqual(partial.presenter.shows, shows)
        XCTAssertTrue(partial.session.candidates.rows.isEmpty)
        try await partial.drain()

        let translated = Fixture()
        translated.session.activate(capsLock: false)
        try await translated.type("nihao")
        try await translated.resolve([Candidate(text: "你好", consumedCount: 5)])
        try await until { !translated.translator.requests.isEmpty }
        let translatedShows = translated.presenter.shows
        XCTAssertTrue(translated.session.handleCapsLock(true, host: translated.host))
        XCTAssertEqual(translated.host.inserted, ["nihao"])
        translated.translator.complete(["Hello"])
        try await settle()
        XCTAssertFalse(translated.presenter.visible)
        XCTAssertEqual(translated.presenter.shows, translatedShows)
        try await translated.drain()
    }

    @MainActor static func capsLockStateSurvivesActivationAndIsShared() async throws {
        let state = InputModeState()
        let first = Fixture(modeState: state), second = Fixture(modeState: state)
        first.session.activate(capsLock: false)
        XCTAssertTrue(first.session.handleCapsLock(true, host: first.host))
        first.session.deactivate()
        second.session.activate(capsLock: false)
        XCTAssertEqual(second.session.mode, .englishDirect, "A physical change while another input source was active only resets the baseline")
        XCTAssertFalse(second.session.handleCapsLock(false, host: second.host))
        XCTAssertFalse(second.key(0, "a"))
        XCTAssertTrue(second.session.handleCapsLock(true, host: second.host))
        XCTAssertEqual(first.session.mode, .chinesePinyin, "Controllers of this input method share the remembered mode")
        try await second.type("NI", capsLock: true)
        second.session.deactivate()
        XCTAssertEqual(second.host.inserted, ["ni"])
        first.session.activate(capsLock: true)
        XCTAssertEqual(first.session.mode, .chinesePinyin)
        XCTAssertFalse(first.session.handleCapsLock(true, host: first.host))
        XCTAssertTrue(first.session.handleCapsLock(false, host: first.host))
        XCTAssertEqual(second.session.mode, .englishDirect)

        let independent = Fixture()
        independent.session.activate(capsLock: true)
        XCTAssertEqual(independent.session.mode, .chinesePinyin, "An independent mode state is not affected by another input method's state")
        XCTAssertFalse(independent.session.handleCapsLock(true, host: independent.host))
        try await first.drain()
        try await second.drain()
        try await independent.drain()
    }

    @MainActor static func capsLockCommitReentry() async throws {
        let f = Fixture()
        f.session.activate(capsLock: false)
        try await f.type("nihao")
        f.host.onCommit = { [weak f] in
            guard let f else { return }
            XCTAssertEqual(f.session.mode, .englishDirect, "Mode changes before calling a potentially reentrant host")
            XCTAssertFalse(f.session.handleCapsLock(true, host: f.host))
            f.session.deactivate()
        }
        XCTAssertTrue(f.session.handleCapsLock(true, host: f.host))
        XCTAssertEqual(f.host.inserted, ["nihao"], "Lifecycle reentry must not commit a second copy")
        XCTAssertTrue(f.session.composition.isEmpty)
        f.provider.complete([Candidate(text: "你好", consumedCount: 5)])
        try await settle()
        XCTAssertFalse(f.presenter.visible)
        XCTAssertTrue(f.translator.requests.isEmpty)
        f.host.onCommit = nil
        try await f.drain()
    }

    @MainActor static func emojiFilteringKeepsSelectionAndFallbackCorrect() async throws {
        let f = Fixture()
        try await f.type("nihao")
        try await f.resolve([Candidate(text: "👋", consumedCount: 5), Candidate(text: "你好", consumedCount: 5),
                             Candidate(text: "你好👋", consumedCount: 5), Candidate(text: "你", consumedCount: 2)])
        XCTAssertEqual(f.presenter.last?.rows.map(\.text), ["你好", "你"])
        try await until { !f.translator.requests.isEmpty }
        XCTAssertEqual(f.translator.requests.first?.sources, ["你好", "你"])
        XCTAssertTrue(f.key(18, "1"))
        XCTAssertEqual(f.host.inserted, ["你好"])
        try await f.drain()

        let empty = Fixture()
        try await empty.type("nihao")
        XCTAssertTrue(empty.key(49, " "))
        empty.provider.complete([Candidate(text: "👋", consumedCount: 5)])
        try await until { !empty.host.inserted.isEmpty }
        XCTAssertEqual(empty.host.inserted, ["nihao"])
        XCTAssertTrue(empty.translator.requests.isEmpty)
        XCTAssertFalse(empty.presenter.visible)
        try await empty.drain()
    }

    @MainActor static func cancellationReentryAndInvalidCandidates() async throws {
        let f = Fixture()
        try await f.type("nihao")
        f.host.onMark = { [weak f] in f?.session.deactivate() }
        f.session.cancel()
        XCTAssertTrue(f.host.inserted.isEmpty, "Cancelling must not submit through a reentrant host callback")
        XCTAssertEqual(f.host.marked, "")
        f.host.onMark = nil
        try await f.drain()

        let invalid = Fixture()
        try await invalid.type("nihao")
        XCTAssertTrue(invalid.key(49, " "))
        invalid.provider.complete([Candidate(text: " \n", consumedCount: 5)])
        try await until { !invalid.host.inserted.isEmpty }
        XCTAssertEqual(invalid.host.inserted, ["nihao"])
        XCTAssertFalse(invalid.presenter.visible)
        try await invalid.drain()
    }

    @MainActor static func returnsAndLateResponses() async throws {
        let f = Fixture()
        XCTAssertFalse(f.key(36, "\r")); XCTAssertFalse(f.key(76, "\r")); XCTAssertFalse(f.key(51, "\u{8}"))
        try await f.type("nihao")
        XCTAssertEqual(f.host.marked, "nihao")
        XCTAssertTrue(f.key(36, "\r"))
        XCTAssertEqual(f.host.inserted, ["nihao"])
        f.provider.complete([Candidate(text: "你好", consumedCount: 5)])
        try await settle()
        XCTAssertFalse(f.presenter.visible)
        XCTAssertEqual(f.presenter.shows, 0)
        XCTAssertTrue(f.translator.requests.isEmpty)
        XCTAssertFalse(f.key(36, "\r"))

        try await f.type("pingying")
        try await f.resolve([Candidate(text: "瓶", consumedCount: 4)])
        try await until { !f.translator.requests.isEmpty }
        XCTAssertTrue(f.key(49, " "))
        XCTAssertEqual(f.host.marked, "瓶ying")
        try await until { !f.provider.requests.isEmpty }
        let before = f.presenter.shows
        XCTAssertTrue(f.key(76, "\r"))
        XCTAssertEqual(f.host.inserted.last, "瓶ying")
        f.provider.complete([Candidate(text: "赢", consumedCount: 4)])
        f.translator.complete(["Bottle"])
        try await settle()
        XCTAssertFalse(f.presenter.visible)
        XCTAssertEqual(f.presenter.shows, before)

        try await f.type("nihao")
        try await f.resolve([Candidate(text: "你好", consumedCount: 5)])
        try await until { !f.translator.requests.isEmpty }
        XCTAssertTrue(f.key(36, "\r"))
        let lastShow = f.presenter.shows
        f.translator.complete(["Hello"])
        try await settle()
        XCTAssertFalse(f.presenter.visible)
        XCTAssertEqual(f.presenter.shows, lastShow)
        XCTAssertEqual(f.host.inserted, ["nihao", "瓶ying", "nihao"])
        try await f.drain()
    }

    @MainActor static func queuedSelectionAndErrors() async throws {
        let f = Fixture()
        try await f.type("nihao")
        XCTAssertTrue(f.key(25, "9"))
        try await f.resolve([Candidate(text: "你好", consumedCount: 5)])
        XCTAssertTrue(f.presenter.visible)
        XCTAssertTrue(f.host.inserted.isEmpty)
        XCTAssertTrue(f.key(53))
        XCTAssertEqual(f.host.marked, "")
        try await f.drain()

        let early = Fixture()
        try await early.type("nihao")
        XCTAssertTrue(early.key(49, " "))
        early.provider.complete([Candidate(text: "你好", consumedCount: 5)])
        try await until { !early.host.inserted.isEmpty }
        XCTAssertEqual(early.host.inserted, ["你好"])
        XCTAssertFalse(early.presenter.visible)
        try await early.drain()

        let failed = Fixture()
        try await failed.type("nihao")
        failed.provider.fail()
        try await until { failed.presenter.visible }
        XCTAssertEqual(failed.session.candidates.selectedRow?.translation, .unavailable(.engineUnavailable))
        XCTAssertTrue(failed.key(49, " "))
        XCTAssertEqual(failed.host.inserted, ["nihao"])
        try await failed.drain()
    }

    @MainActor static func obsoleteQueriesAndPageTranslations() async throws {
        let f = Fixture()
        try await f.type("n")
        XCTAssertTrue(f.key(0, "i"))
        try await until { f.provider.requests.count == 2 }
        f.provider.complete([Candidate(text: "你", consumedCount: 2)], at: 1)
        try await until { f.presenter.visible }
        f.provider.complete([Candidate(text: "嗯", consumedCount: 1)])
        try await settle()
        XCTAssertEqual(f.session.candidates.selectedRow?.text, "你")
        try await f.drain()

        let page = Fixture()
        try await page.type("nihao")
        try await page.resolve((0..<12).map { Candidate(text: "词\($0)", consumedCount: 5) })
        try await until { page.translator.requests.count == 1 }
        XCTAssertTrue(page.key(121))
        try await until { page.translator.requests.count == 2 }
        XCTAssertTrue(page.key(116))
        try await until { page.translator.requests.count == 3 }
        page.translator.complete(Array(repeating: "Old", count: 9))
        try await settle()
        XCTAssertNil(page.session.candidates.selectedRow?.speechText)
        page.translator.complete(Array(repeating: "Other page", count: 3))
        page.translator.complete(Array(repeating: "Current", count: 9))
        try await until { page.session.candidates.selectedRow?.speechText == "Current" }
        XCTAssertEqual(page.session.candidates.page, 0)
        try await page.drain()

        let short = Fixture()
        try await short.type("nihao")
        try await short.resolve([Candidate(text: "你好", consumedCount: 5), Candidate(text: "你号", consumedCount: 5)])
        try await until { !short.translator.requests.isEmpty }
        short.translator.complete(["Hello"])
        try await until { short.session.candidates.rows.first?.translation == .unavailable(.failed) }
        XCTAssertTrue(short.session.candidates.rows.allSatisfy { $0.speechText == nil })
        try await short.drain()
    }

    @MainActor static func lifecycleModeAndSpeech() async throws {
        let f = Fixture()
        try await f.type("nihao")
        XCTAssertEqual(f.provider.requests.first?.context, "前文")
        try await f.resolve([Candidate(text: "你好", consumedCount: 5)])
        XCTAssertTrue(f.key(15, "R", flags: [.control, .shift]))
        XCTAssertTrue(f.speaker.spoken.isEmpty)
        try await until { !f.translator.requests.isEmpty }
        f.translator.complete(["Hello"])
        try await until { f.session.candidates.selectedRow?.speechText == "Hello" }
        XCTAssertTrue(f.key(15, "R", flags: [.control, .shift]))
        XCTAssertTrue(f.key(15, "R", flags: [.control, .shift], repeatKey: true))
        XCTAssertEqual(f.speaker.spoken, ["Hello"])
        XCTAssertEqual(f.host.marked, "nihao")
        XCTAssertTrue(f.host.inserted.isEmpty)
        XCTAssertTrue(f.key(49, " ", flags: [.control, .shift]))
        XCTAssertEqual(f.session.mode, .englishDirect)
        XCTAssertEqual(f.host.inserted, ["nihao"])
        XCTAssertFalse(f.key(0, "hello"))
        XCTAssertFalse(f.key(49, " ", flags: [.control, .shift, .command]))
        XCTAssertEqual(f.session.mode, .englishDirect)
        XCTAssertTrue(f.key(49, " ", flags: [.control, .shift]))
        try await f.type("nihao")
        f.session.cancel()
        XCTAssertEqual(f.host.marked, "")
        f.provider.complete([Candidate(text: "你好", consumedCount: 5)])
        try await settle()
        XCTAssertFalse(f.presenter.visible)
        XCTAssertTrue(f.session.composition.isEmpty)
        try await f.drain()

        let switched = Fixture()
        try await switched.type("nihao")
        let newHost = Host()
        newHost.context = "新宿主"
        XCTAssertTrue(switched.session.handle(KeyStroke(code: 0, characters: "xie"), host: newHost))
        XCTAssertEqual(switched.host.inserted, ["nihao"])
        XCTAssertEqual(newHost.marked, "xie")
        try await until { switched.provider.requests.count == 2 }
        XCTAssertEqual(switched.provider.requests.last?.context, "新宿主")
        switched.session.deactivate()
        XCTAssertEqual(newHost.inserted, ["xie"])
        try await switched.drain()
    }
}
