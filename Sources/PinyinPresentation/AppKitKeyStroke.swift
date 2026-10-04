import AppKit
import PinyinApplication

extension KeyStroke {
    @MainActor public init(event: NSEvent) {
        var flags: KeyModifiers = []
        if event.modifierFlags.contains(.shift) { flags.insert(.shift) }
        if event.modifierFlags.contains(.control) { flags.insert(.control) }
        if event.modifierFlags.contains(.option) { flags.insert(.option) }
        if event.modifierFlags.contains(.command) { flags.insert(.command) }
        self.init(code: event.keyCode, characters: event.characters ?? "", modifiers: flags,
                  isRepeat: event.isARepeat, capsLock: event.modifierFlags.contains(.capsLock))
    }
}

/// Modifier and mouse events do not have keyDown's characters/isARepeat fields.
public enum InputEvent {
    case key(KeyStroke)
    case capsLock(Bool)
    case mouseDown
    case unhandled

    public static let recognizedEvents: NSEvent.EventTypeMask = [
        .keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown
    ]

    @MainActor public init(event: NSEvent) {
        switch event.type {
        case .keyDown: self = .key(KeyStroke(event: event))
        case .flagsChanged where event.keyCode == 57:
            self = .capsLock(event.modifierFlags.contains(.capsLock))
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: self = .mouseDown
        default: self = .unhandled
        }
    }
}
