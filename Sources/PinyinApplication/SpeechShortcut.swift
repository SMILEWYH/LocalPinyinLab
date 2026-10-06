/// A two- or three-key chord using macOS physical key codes.
/// Names are derived from the supported keys rather than persisted user input.
public struct SpeechShortcut: Equatable, Sendable, Codable {
    public let modifiers: KeyModifiers
    public let keyCode: UInt16?

    public static let `default` = SpeechShortcut(modifiers: [.command, .option])!

    public init?(modifiers: KeyModifiers, keyCode: UInt16? = nil) {
        guard Self.validationMessage(modifiers: modifiers, keyCode: keyCode) == nil else { return nil }
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    public var isModifierOnly: Bool { keyCode == nil }

    public var displayName: String {
        let names: [(KeyModifiers, String)] = [(.control, "Control"), (.shift, "Shift"), (.command, "Command"), (.option, "Option")]
        var parts = names.compactMap { modifiers.contains($0.0) ? $0.1 : nil }
        if let keyCode, let key = Self.keyOptions.first(where: { $0.code == keyCode }) { parts.append(key.name) }
        return parts.joined(separator: " + ")
    }

    public static func validationMessage(modifiers: KeyModifiers, keyCode: UInt16? = nil) -> String? {
        let supported: KeyModifiers = [.control, .shift, .option, .command]
        guard modifiers.subtracting(supported).isEmpty else { return "只支持 Command、Option、Control 和 Shift 修饰键。" }
        let count = modifiers.rawValue.nonzeroBitCount + (keyCode == nil ? 0 : 1)
        guard (2...3).contains(count) else { return "请选择两个或三个按键组成快捷键。" }
        if let keyCode {
            guard keyOptions.contains(where: { $0.code == keyCode }) else { return "不支持这个普通按键，请从列表中选择。" }
            if keyCode == 49 && modifiers == [.control, .shift] { return "Control + Shift + Space 已用于切换中英文。" }
            // These keys already control composition even when Shift is held.
            let compositionKeys: Set<UInt16> = [18, 19, 20, 21, 23, 22, 26, 28, 25, 36, 49, 51, 53, 76, 116, 121, 123, 125, 126]
            if modifiers == [.shift] && compositionKeys.contains(keyCode) { return "这个组合已用于选词或编辑拼音，请选择其他按键。" }
        }
        return nil
    }

    public static let keyOptions: [(code: UInt16, name: String)] = [
        (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"), (5, "G"), (4, "H"),
        (34, "I"), (38, "J"), (40, "K"), (37, "L"), (46, "M"), (45, "N"), (31, "O"), (35, "P"),
        (12, "Q"), (15, "R"), (1, "S"), (17, "T"), (32, "U"), (9, "V"), (13, "W"), (7, "X"),
        (16, "Y"), (6, "Z"), (29, "0"), (18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"),
        (22, "6"), (26, "7"), (28, "8"), (25, "9"), (48, "Tab"), (49, "Space"), (36, "Return"),
        (53, "Esc"), (51, "Delete"), (117, "Forward Delete"), (76, "Enter"), (123, "Left"),
        (124, "Right"), (125, "Down"), (126, "Up"), (115, "Home"), (119, "End"), (116, "Page Up"),
        (121, "Page Down"), (27, "-"), (24, "="), (33, "["), (30, "]"), (42, "\\"), (41, ";"),
        (39, "'"), (43, ","), (47, "."), (44, "/"), (50, "`"), (122, "F1"), (120, "F2"),
        (99, "F3"), (118, "F4"), (96, "F5"), (97, "F6"), (98, "F7"), (100, "F8"), (101, "F9"),
        (109, "F10"), (103, "F11"), (111, "F12")
    ]

    private enum CodingKeys: String, CodingKey { case modifiers, keyCode }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let modifiers = KeyModifiers(rawValue: try container.decode(Int.self, forKey: .modifiers))
        let keyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode)
        guard let shortcut = Self(modifiers: modifiers, keyCode: keyCode) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: Self.validationMessage(modifiers: modifiers, keyCode: keyCode) ?? "Invalid speech shortcut"))
        }
        self = shortcut
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
        try container.encodeIfPresent(keyCode, forKey: .keyCode)
    }
}
