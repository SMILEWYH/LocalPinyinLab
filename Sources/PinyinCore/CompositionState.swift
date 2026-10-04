import Foundation

/// Owns the exact raw input: selected segments plus the unconverted suffix never exceed 128.
public struct CompositionState: Sendable, Equatable {
    public struct Segment: Sendable, Equatable {
        public let text: String
        public let pinyin: String
    }

    public private(set) var pending = ""
    public private(set) var segments: [Segment] = []

    public init() {}

    public var selectedText: String { segments.map(\.text).joined() }
    public var markedText: String { selectedText + pending }
    public var isEmpty: Bool { pending.isEmpty && segments.isEmpty }
    public var inputCount: Int { pending.count + segments.reduce(0) { $0 + $1.pinyin.count } }

    /// Rejects the whole append if its format or total composition length is invalid.
    @discardableResult
    public mutating func append(_ text: String) -> Bool {
        guard PinyinRules.isValid(text), text.count <= PinyinRules.maxInputLength - inputCount else { return false }
        pending += text
        return true
    }

    /// Selection consumes a nonempty prefix atomically and preserves its exact original spelling.
    @discardableResult
    public mutating func choose(_ candidate: Candidate) -> Bool {
        guard CandidateTextPolicy.allows(candidate.text),
              candidate.consumedCount > 0, candidate.consumedCount <= pending.count else { return false }
        let raw = String(pending.prefix(candidate.consumedCount))
        segments.append(Segment(text: candidate.text, pinyin: raw))
        pending.removeFirst(candidate.consumedCount)
        return true
    }

    @discardableResult
    public mutating func undoSelection() -> Bool {
        guard let segment = segments.popLast() else { return false }
        pending = segment.pinyin + pending
        return true
    }

    public mutating func backspace() {
        if !pending.isEmpty { pending.removeLast() }
        else { undoSelection() }
    }
}
