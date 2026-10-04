import Foundation

/// Shared limits and transformations for raw pinyin and ephemeral document context.
public enum PinyinRules {
    public static let maxInputLength = 128
    public static let maxContextLength = 128
    public static let pageSize = 9

    public static func isValid(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= maxInputLength && text.unicodeScalars.allSatisfy {
            (97...122).contains($0.value) || $0.value == 39
        }
    }

    /// Keeps a contiguous suffix without splitting a grapheme or exceeding the UTF-16 limit.
    public static func boundedContext(_ text: String) -> String {
        var result = ""
        var length = 0
        for character in text.reversed() {
            let part = String(character)
            guard part.utf16.count <= maxContextLength - length else { break }
            result = part + result
            length += part.utf16.count
        }
        return result
    }

    /// Maps an engine reading to the input prefix, including its trailing syllable separators.
    public static func consumedCount(reading: String, in pinyin: String) -> Int? {
        guard isValid(pinyin) else { return nil }
        let normalized = reading.filter { $0 != "'" }
        guard !normalized.isEmpty else { return nil }
        var matched = ""
        let characters = Array(pinyin)
        for (index, character) in characters.enumerated() {
            if character != "'" { matched.append(character) }
            guard normalized.hasPrefix(matched) else { return nil }
            if matched == normalized {
                var count = index + 1
                while count < characters.count && characters[count] == "'" { count += 1 }
                return count
            }
        }
        return nil
    }
}
