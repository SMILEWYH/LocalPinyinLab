import Foundation

/// Owns one absolute selection index; page and highlight cannot diverge from the rows.
public struct CandidateList: Sendable, Equatable {
    public private(set) var rows: [CandidateRow]
    public private(set) var selectedIndex: Int?

    public init(rows: [CandidateRow] = []) {
        self.rows = rows
        selectedIndex = rows.isEmpty ? nil : 0
    }

    public var page: Int { (selectedIndex ?? 0) / PinyinRules.pageSize }
    public var highlighted: Int { (selectedIndex ?? 0) % PinyinRules.pageSize }
    public var totalPages: Int { rows.isEmpty ? 0 : (rows.count - 1) / PinyinRules.pageSize + 1 }
    public var visibleIndices: [Int] {
        let start = page * PinyinRules.pageSize
        return Array(start..<(start + min(PinyinRules.pageSize, rows.count - start)))
    }
    public var visibleRows: [CandidateRow] { visibleIndices.map { rows[$0] } }
    public var selectedRow: CandidateRow? { selectedIndex.map { rows[$0] } }

    public mutating func replace(_ rows: [CandidateRow]) {
        self.rows = rows
        selectedIndex = rows.isEmpty ? nil : 0
    }

    public mutating func clear() { replace([]) }

    /// A target-language change keeps candidate ordering and selection intact.
    /// Engine diagnostics are independent of translation and remain visible.
    public mutating func resetTranslations() {
        for index in rows.indices {
            switch rows[index].translation {
            case .unavailable(.noCandidates), .unavailable(.engineUnavailable): continue
            default:
                rows[index].translation = rows[index].needsTranslation ? .pending : .notRequired
            }
        }
    }

    public mutating func move(by offset: Int) {
        guard let selectedIndex else { return }
        self.selectedIndex = Self.moving(selectedIndex, by: offset, maximum: rows.count - 1)
    }

    /// Paging always selects the destination page's first row, including at either boundary.
    public mutating func movePage(by offset: Int) {
        guard !rows.isEmpty else { return }
        selectedIndex = Self.moving(page, by: offset, maximum: totalPages - 1) * PinyinRules.pageSize
    }

    /// Converts a zero-based number-key position to an existing row on the current page.
    public func indexOnPage(_ offset: Int) -> Int? {
        guard (0..<PinyinRules.pageSize).contains(offset) else { return nil }
        let index = page * PinyinRules.pageSize + offset
        return rows.indices.contains(index) ? index : nil
    }

    /// Rejects a stale translation when its expected source no longer occupies this index.
    @discardableResult
    public mutating func updateTranslation(at index: Int, source: String, state: TranslationState) -> Bool {
        guard rows.indices.contains(index), rows[index].text == source else { return false }
        rows[index].translation = state
        return true
    }

    private static func moving(_ value: Int, by offset: Int, maximum: Int) -> Int {
        if offset > 0 { return offset >= maximum - value ? maximum : value + offset }
        return offset <= -value ? 0 : value + offset
    }
}
