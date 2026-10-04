import AppKit
import PinyinApplication

extension KeyStroke {
    @MainActor public init(event: NSEvent) {
        var flags: KeyModifiers = []
        if event.modifierFlags.contains(.shift) { flags.insert(.shift) }
        if event.modifierFlags.contains(.control) { flags.insert(.control) }
        if event.modifierFlags.contains(.option) { flags.insert(.option) }
        if event.modifierFlags.contains(.command) { flags.insert(.command) }
        self.init(code: event.keyCode, characters: event.characters ?? "", modifiers: flags, isRepeat: event.isARepeat)
    }
}
