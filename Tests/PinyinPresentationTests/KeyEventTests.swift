import AppKit
import PinyinApplication
import PinyinPresentation
import TestSupport

@main struct KeyEventTests {
    @MainActor static func main() {
        for (code, flags, speech, toggle): (UInt16, NSEvent.ModifierFlags, Bool, Bool) in [
            (15, [.control, .shift], true, false), (15, [.control], false, false),
            (15, [.control, .shift, .option], false, false), (49, [.control, .shift], false, true),
            (49, [.control, .shift, .command], false, false), (49, [.option], false, false)
        ] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: "r",
                charactersIgnoringModifiers: "r", isARepeat: true, keyCode: code)!
            let key = KeyStroke(event: event)
            XCTAssertEqual(key.requestsSpeech, speech)
            XCTAssertEqual(key.switchesMode, toggle)
            XCTAssertTrue(key.isRepeat)
            XCTAssertEqual(key.characters, "r")
        }
        print("PASS: NSEvent boundary, exact modifiers, shortcut separation and repeat forwarding")
    }
}
