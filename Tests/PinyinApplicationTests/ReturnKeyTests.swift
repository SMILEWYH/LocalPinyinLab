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
    func precedingContext() -> String { context }
    func setMarkedText(_ text: String) { marked = text; onMark?() }
    func commit(_ text: String) { inserted.append(text); marked = "" }
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
    lazy var session = InputSession(provider: provider, translator: translator, speaker: speaker, presenter: presenter)
    @discardableResult func key(_ code: UInt16, _ text: String = "", flags: KeyModifiers = [], repeatKey: Bool = false) -> Bool {
        session.handle(KeyStroke(code: code, characters: text, modifiers: flags, isRepeat: repeatKey), host: host)
    }
    func type(_ text: String) async throws {
        XCTAssertTrue(key(0, text))
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
        print("PASS: Return, queued selection, query/page races, speech, host lifecycle and mode regression cases")
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
