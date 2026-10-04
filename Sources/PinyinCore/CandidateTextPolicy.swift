import Foundation

/// Product policy for selectable text, shared by engine decoding and input sessions.
public enum CandidateTextPolicy {
    public static func allows(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !containsEmoji(text)
    }

    private static func containsEmoji(_ text: String) -> Bool {
        text.contains { character in
            let scalars = Array(character.unicodeScalars)
            // These text-default faces/hearts still look like emoticons to the user.
            if scalars.contains(where: { [0x2639, 0x263A, 0x2665, 0x2763, 0x2764].contains($0.value) }) { return true }
            // Digits, # and * alone have Emoji=true but are ordinary text, not keycaps.
            if let first = scalars.first,
               (first.value == 35 || first.value == 42 || (48...57).contains(first.value)),
               scalars.contains(where: { $0.value == 0x20E3 }) { return true }
            // Also catch minimally qualified joined sequences without variation selectors.
            if scalars.contains(where: { $0.value == 0x200D }),
               scalars.contains(where: { $0.value > 127 && $0.properties.isEmoji }) { return true }
            for index in scalars.indices where scalars[index].properties.isEmoji {
                let next = index + 1 < scalars.count ? scalars[index + 1].value : nil
                // Default emoji stay excluded even when requested in monochrome text style.
                if scalars[index].properties.isEmojiPresentation || next == 0xFE0F { return true }
            }
            return false
        }
    }
}
