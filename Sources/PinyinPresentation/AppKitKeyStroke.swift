import AppKit
import PinyinApplication

extension KeyStroke {
    @MainActor public init(event: NSEvent, capsLockOverride: Bool? = nil) {
        self.init(code: event.keyCode, characters: event.characters ?? "", modifiers: KeyModifiers(event.modifierFlags),
                  isRepeat: event.isARepeat, capsLock: capsLockOverride ?? event.modifierFlags.contains(.capsLock),
                  capsLockForText: event.modifierFlags.contains(.capsLock))
    }
}

public extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.command) { insert(.command) }
    }
}

/// Modifier and mouse events do not have keyDown's characters/isARepeat fields.
public enum InputEvent {
    case key(KeyStroke)
    case capsLock(Bool, modifiers: KeyModifiers)
    case modifiersChanged(KeyModifiers)
    case shortcutCancelled
    case mouseDown
    case unhandled

    public static let recognizedEvents: NSEvent.EventTypeMask = [
        .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
    ]

    @MainActor public init(event: NSEvent, capsLockOverride: Bool? = nil) {
        switch event.type {
        case .keyDown: self = .key(KeyStroke(event: event, capsLockOverride: capsLockOverride))
        case .flagsChanged where event.keyCode == 57:
            // Real modifier edges remain authoritative while an earlier LED update is pending.
            self = .capsLock(event.modifierFlags.contains(.capsLock), modifiers: KeyModifiers(event.modifierFlags))
        case .flagsChanged where event.modifierFlags.contains(.function):
            self = .shortcutCancelled
        case .flagsChanged where [54, 55, 56, 58, 59, 60, 61, 62].contains(event.keyCode):
            self = .modifiersChanged(KeyModifiers(event.modifierFlags))
        case .keyUp, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel:
            self = .shortcutCancelled
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: self = .mouseDown
        default: self = .unhandled
        }
    }
}
