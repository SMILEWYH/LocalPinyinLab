import Foundation

struct CompositionState {
    struct Segment { let text: String; let pinyin: String }
    var pending = ""
    private(set) var segments: [Segment] = []
    var selectedText: String { segments.map(\.text).joined() }
    var markedText: String { selectedText + pending }
    var isEmpty: Bool { pending.isEmpty && segments.isEmpty }
    var inputCount: Int { pending.count + segments.reduce(0) { $0 + $1.pinyin.count } }

    mutating func choose(_ candidate: Candidate) -> Bool {
        guard candidate.consumedCount > 0, candidate.consumedCount <= pending.count else { return false }
        let raw = String(pending.prefix(candidate.consumedCount))
        segments.append(Segment(text: candidate.text, pinyin: raw))
        pending.removeFirst(candidate.consumedCount)
        return true
    }

    mutating func undoSelection() -> Bool {
        guard let segment = segments.popLast() else { return false }
        pending = segment.pinyin + pending
        return true
    }

    mutating func backspace() {
        if !pending.isEmpty { pending.removeLast() }
        else { _ = undoSelection() }
    }
}
