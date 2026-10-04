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
        for (flags, expected): (NSEvent.ModifierFlags, Bool) in [(.capsLock, true), ([], false)] {
            let event = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: "",
                charactersIgnoringModifiers: "", isARepeat: false, keyCode: 57)!
            guard case .capsLock(let enabled) = InputEvent(event: event) else {
                fatalError("Caps Lock must not be converted into a text key")
            }
            XCTAssertEqual(enabled, expected)
        }
        let shift = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .shift,
            timestamp: 0, windowNumber: 0, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: false, keyCode: 56)!
        guard case .unhandled = InputEvent(event: shift) else { fatalError("Shift alone must not switch mode") }
        let capsText = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .capsLock,
            timestamp: 0, windowNumber: 0, context: nil, characters: "A",
            charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
        guard case .key(let mapped) = InputEvent(event: capsText) else { fatalError("Missing text event") }
        XCTAssertTrue(mapped.capsLock)
        XCTAssertEqual(mapped.modifiers, [])
        XCTAssertEqual(mapped.textIgnoringCapsLock, "a")
        let mouse = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        guard case .mouseDown = InputEvent(event: mouse) else { fatalError("Missing outside-click event") }
        XCTAssertTrue(InputEvent.recognizedEvents.contains([.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]))
        print("PASS: NSEvent keys, Caps Lock modifier edges, exact shortcuts and mouse boundary")
    }
}
