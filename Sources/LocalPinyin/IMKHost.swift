import AppKit
import InputMethodKit
import Carbon
import PinyinCore
import PinyinApplication

@MainActor final class IMKHost: InputHost {
    let client: any IMKTextInput
    private let replacement = NSRange(location: NSNotFound, length: 0)
    init(client: any IMKTextInput) { self.client = client }

    func precedingContext() -> String {
        guard !IsSecureEventInputEnabled() else { return "" }
        let selection = client.selectedRange()
        guard selection.location != NSNotFound, selection.location > 0 else { return "" }
        let length = min(PinyinRules.maxContextLength, selection.location)
        let range = NSRange(location: selection.location - length, length: length)
        guard let text = client.attributedSubstring(from: range)?.string else { return "" }
        return PinyinRules.boundedContext(text)
    }

    func setMarkedText(_ text: String) {
        client.setMarkedText(text, selectionRange: NSRange(location: text.utf16.count, length: 0), replacementRange: replacement)
    }

    func commit(_ text: String) { client.insertText(text, replacementRange: replacement) }

    var anchor: NSRect {
        var rectangle = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rectangle)
        return rectangle
    }
}
