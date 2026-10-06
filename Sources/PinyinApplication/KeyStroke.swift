public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let shift = Self(rawValue: 1 << 0)
    public static let control = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let command = Self(rawValue: 1 << 3)
}

/// Platform-neutral event. Physical key codes preserve the existing shortcut behavior.
public struct KeyStroke: Sendable {
    public let code: UInt16
    public let characters: String
    public let modifiers: KeyModifiers
    public let isRepeat: Bool
    public let capsLock: Bool
    // The captured lock may lag behind logical mode during hardware synchronization.
    // It still determines how the OS generated `characters` for this event.
    private let capturedCapsLock: Bool

    public init(code: UInt16, characters: String = "", modifiers: KeyModifiers = [], isRepeat: Bool = false, capsLock: Bool = false,
                capsLockForText: Bool? = nil) {
        self.code = code
        self.characters = characters
        self.modifiers = modifiers
        self.isRepeat = isRepeat
        self.capsLock = capsLock
        capturedCapsLock = capsLockForText ?? capsLock
    }

    public var requestsSpeech: Bool { code == 15 && modifiers == [.control, .shift] }
    public var switchesMode: Bool { code == 49 && modifiers == [.control, .shift] }
    public var passesThrough: Bool { !modifiers.intersection([.control, .option, .command]).isEmpty }

    /// Caps Lock selects our input mode; Shift still controls ASCII letter case.
    /// Preserve shortcuts, non-ASCII text, dead keys, symbols and keyboard layout.
    public var textIgnoringCapsLock: String {
        guard capturedCapsLock, !passesThrough, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ (65...90).contains($0.value) || (97...122).contains($0.value) }) else { return characters }
        return modifiers.contains(.shift) ? characters.uppercased() : characters.lowercased()
    }

    /// The input method's uppercase lock is independent of the hardware LED.
    /// Shift remains useful for symbols while ASCII letters stay uppercase.
    public func text(uppercaseLocked: Bool) -> String {
        guard uppercaseLocked, !passesThrough, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ (65...90).contains($0.value) || (97...122).contains($0.value) }) else { return textIgnoringCapsLock }
        return characters.uppercased()
    }
}
