/// Chinese-mode punctuation; letters, digits and unmapped symbols remain unchanged.
public enum ChinesePunctuation {
    private static let replacements: [String: String] = [
        ",": "，", ".": "。", "?": "？", "!": "！",
        ":": "：", ";": "；", "(": "（", ")": "）",
        "[": "【", "]": "】", "<": "《", ">": "》",
        "\\": "、", "^": "……", "_": "——", "~": "～", "$": "￥"
    ]

    public static func text(for input: String, preceding context: String = "") -> String? {
        switch input {
        case "\"": return quote(open: "“", close: "”", context: context)
        case "'": return quote(open: "‘", close: "’", context: context)
        default: return replacements[input]
        }
    }

    // Read the document instead of keeping a toggle that becomes stale when the
    // user moves the caret, deletes a quote, or switches to another document.
    private static func quote(open: Character, close: Character, context: String) -> String {
        let last = context.last(where: { $0 == open || $0 == close })
        return String(last == open ? close : open)
    }
}
