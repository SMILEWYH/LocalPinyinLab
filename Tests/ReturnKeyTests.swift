// Executes the actual InputController event/async logic with an in-memory host,
// controllable candidate/translation providers, and a non-windowing panel.
// It does not register an input source or modify the installed service.
import AppKit

@MainActor protocol IMKTextInput: AnyObject {
    func insertText(_ text: Any!, replacementRange: NSRange)
    func setMarkedText(_ text: Any!, selectionRange: NSRange, replacementRange: NSRange)
    func selectedRange() -> NSRange
    func attributedSubstring(from range: NSRange) -> NSAttributedString?
    func attributes(forCharacterIndex index: Int, lineHeightRectangle rect: UnsafeMutablePointer<NSRect>!) -> NSDictionary?
}
@MainActor class IMKInputController: NSObject {
    func activateServer(_ sender: Any!) {}
    func deactivateServer(_ sender: Any!) {}
    func handle(_ event: NSEvent!, client sender: Any!) -> Bool { false }
}
@MainActor final class Host: NSObject, IMKTextInput {
    var inserted: [String] = []
    var marked = ""
    func insertText(_ text: Any!, replacementRange: NSRange) { inserted.append(text as! String); marked = "" }
    func setMarkedText(_ text: Any!, selectionRange: NSRange, replacementRange: NSRange) { marked = text as! String }
    func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
    func attributedSubstring(from range: NSRange) -> NSAttributedString? { nil }
    func attributes(forCharacterIndex index: Int, lineHeightRectangle rect: UnsafeMutablePointer<NSRect>!) -> NSDictionary? {
        rect.pointee = NSRect(x: 100, y: 100, width: 1, height: 16); return nil
    }
}
@MainActor final class CandidatePanel {
    static var visible = false
    static var shows = 0
    func show(rows: [Candidate], pinyin: String, selected: Int, page: Int, totalPages: Int, anchor: NSRect, status: String? = nil) {
        Self.visible = true; Self.shows += 1
    }
    func hide() { Self.visible = false }
    func showLoading(pinyin: String) {}
}
@MainActor final class PinyinSession {
    static let shared = PinyinSession()
    var waiting: [CheckedContinuation<[Candidate], Error>] = []
    func warm() {}
    func candidates(for pinyin: String, context: String = "") async throws -> [Candidate] {
        try await withCheckedThrowingContinuation { waiting.append($0) }
    }
    func complete(_ rows: [Candidate]) { waiting.removeFirst().resume(returning: rows) }
}
@MainActor final class AppleTranslator {
    enum Status { case installed }
    static var waiting: [CheckedContinuation<[String], Error>] = []
    func status() async -> Status { .installed }
    func translate(_ sources: [String]) async throws -> [String] {
        try await withCheckedThrowingContinuation { Self.waiting.append($0) }
    }
    static func complete(_ text: [String]) { waiting.removeFirst().resume(returning: text) }
}

@main struct ReturnKeyTests {
    @MainActor static func main() async throws {
        func event(_ code: UInt16, _ text: String) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: text,
                charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
        }
        func until(_ condition: () -> Bool) async throws {
            for _ in 0..<200 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(5))
            }
            fatalError("Timed out waiting for controlled async step")
        }
        func settle() async throws { try await Task.sleep(for: .milliseconds(30)) }
        let host = Host()
        let controller = InputController()
        precondition(!controller.handle(event(36, "\r"), client: host))
        precondition(!controller.handle(event(76, "\r"), client: host))
        precondition(!controller.handle(event(51, "\u{8}"), client: host))
        precondition(host.inserted.isEmpty)
        print("PASS: empty composition passes Return, keypad Enter and Delete to host")

        precondition(controller.handle(event(45, "nihao"), client: host))
        try await until { !PinyinSession.shared.waiting.isEmpty }
        precondition(host.marked == "nihao")
        precondition(controller.handle(event(36, "\r"), client: host))
        precondition(host.inserted == ["nihao"] && host.marked.isEmpty)
        PinyinSession.shared.complete([Candidate(text: "你好", translation: "", consumedCount: 5)])
        try await settle()
        precondition(!CandidatePanel.visible && CandidatePanel.shows == 0)
        precondition(AppleTranslator.waiting.isEmpty)
        precondition(!controller.handle(event(36, "\r"), client: host))
        print("PASS: Return commits raw nihao without newline; late candidate response discarded")

        precondition(controller.handle(event(35, "pingying"), client: host))
        try await until { !PinyinSession.shared.waiting.isEmpty }
        PinyinSession.shared.complete([Candidate(text: "瓶", translation: "", consumedCount: 4)])
        try await until { CandidatePanel.visible && !AppleTranslator.waiting.isEmpty }
        precondition(controller.handle(event(49, " "), client: host))
        precondition(host.marked == "瓶ying")
        try await until { !PinyinSession.shared.waiting.isEmpty }
        let beforePrefixReturn = CandidatePanel.shows
        precondition(controller.handle(event(76, "\r"), client: host))
        precondition(host.inserted.last == "瓶ying" && host.marked.isEmpty)
        PinyinSession.shared.complete([Candidate(text: "赢", translation: "", consumedCount: 4)])
        AppleTranslator.complete(["Bottle"])
        try await settle()
        precondition(!CandidatePanel.visible && CandidatePanel.shows == beforePrefixReturn)
        print("PASS: selected Chinese prefix plus pending pinyin committed; late results cannot reopen panel")

        precondition(controller.handle(event(45, "nihao"), client: host))
        try await until { !PinyinSession.shared.waiting.isEmpty }
        PinyinSession.shared.complete([Candidate(text: "你好", translation: "", consumedCount: 5)])
        try await until { CandidatePanel.visible && !AppleTranslator.waiting.isEmpty }
        let beforeTranslationReturn = CandidatePanel.shows
        precondition(controller.handle(event(36, "\r"), client: host))
        precondition(host.inserted.last == "nihao")
        AppleTranslator.complete(["Hello"])
        try await settle()
        precondition(!CandidatePanel.visible && CandidatePanel.shows == beforeTranslationReturn)
        precondition(PinyinSession.shared.waiting.isEmpty && AppleTranslator.waiting.isEmpty)
        print("PASS: Return closes existing panel; late translation does not reopen it")
        print("NOTE: in-memory host/provider test; actual IMK host Return behavior still requires physical acceptance")
    }
}
