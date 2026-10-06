// Swift adaptation of qingjian's AppKit vertical layout; see NOTICE and LICENSE.
import AppKit
import PinyinCore

@MainActor
public final class CandidateView: NSView {
    private static let textFont = NSFont.systemFont(ofSize: 16)
    private static let annotationFont = NSFont.systemFont(ofSize: 12)
    private static let indexFont = NSFont.systemFont(ofSize: 11)
    private static let padding: CGFloat = 8
    private static let gap: CGFloat = 8
    private let size: NSSize

    public override var isFlipped: Bool { true }
    public var preferredSize: NSSize { size }

    public init(rows: [CandidateRow], pinyin: String, highlighted: Int, footer: String,
                maximumSize: NSSize = NSSize(width: 560, height: 700), minimumHeight: CGFloat = 0) {
        precondition(rows.count <= PinyinRules.pageSize)
        // Width depends only on the available screen, never on delayed translations.
        let width = max(1, min(560, maximumSize.width))
        let maximumHeight = max(1, maximumSize.height)
        let padding = min(Self.padding, width / 12, maximumHeight / 12)
        let contentWidth = max(1, width - padding * 2)
        let indexWidth: CGFloat = 12
        let gap = min(Self.gap, contentWidth / 12)
        let columnsWidth = max(2, contentWidth - indexWidth - gap * 2)
        let textWidth = floor(columnsWidth * 0.46)
        let glossWidth = columnsWidth - textWidth
        let headerHeight = min(Self.height(pinyin, font: Self.annotationFont, width: contentWidth, lines: 2) + 8,
                               maximumHeight / 3)
        let footerHeight = min(Self.lineHeight(Self.indexFont) + 8, maximumHeight / 4)
        let availableBodyHeight = max(0, maximumHeight - padding * 2 - headerHeight - footerHeight)
        let rowHeights = rows.enumerated().map { index, row in
            let lines = index == highlighted ? 3 : 1
            return max(Self.height(row.text, font: Self.textFont, width: textWidth, lines: lines),
                       Self.height(row.translationText, font: Self.annotationFont, width: glossWidth, lines: lines)) + 8
        }
        let visible = Self.visibleRows(heights: rowHeights, highlighted: highlighted, availableHeight: availableBodyHeight)
        let minimumBodyHeight = rows.isEmpty ? max(0, minimumHeight - padding * 2 - headerHeight - footerHeight) : 0
        let bodyHeight = min(max(minimumBodyHeight, visible.reduce(CGFloat.zero) { $0 + rowHeights[$1] }), availableBodyHeight)
        size = NSSize(width: width, height: min(maximumHeight, padding * 2 + headerHeight + bodyHeight + footerHeight))
        super.init(frame: NSRect(origin: .zero, size: size))
        appearance = NSAppearance(named: .aqua)
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel(rows.isEmpty ? "拼音候选，查询中" : "拼音候选")
        setAccessibilityValue(pinyin + "，" + footer)
        setAccessibilityHelp("上下方向键选择，空格确认，数字键选词，左右方向键翻页。")

        let header = Self.label(pinyin + "│", font: Self.annotationFont, color: NSColor(white: 0.38, alpha: 1), lines: 2)
        header.frame = NSRect(x: padding, y: padding + 4, width: contentWidth, height: max(0, headerHeight - 8))
        header.setAccessibilityLabel("正在输入：" + pinyin)
        addSubview(header)

        var accessibleRows: [NSView] = []
        var y = padding + headerHeight
        for index in visible {
            let row = rows[index]
            let selected = index == highlighted
            let height = min(rowHeights[index], max(0, padding + headerHeight + bodyHeight - y))
            let rowView = CandidateRowView(selected: selected)
            rowView.frame = NSRect(x: padding / 2, y: y, width: width - padding, height: height)
            rowView.setAccessibilityElement(true)
            rowView.setAccessibilityRole(.row)
            rowView.setAccessibilityLabel(row.accessibilityText(index: index))
            rowView.setAccessibilitySelected(selected)
            rowView.setAccessibilityIndex(index)
            let lines = selected ? 3 : 1
            let number = Self.label(String(index + 1), font: Self.indexFont,
                                    color: selected ? .white : NSColor(white: 0.45, alpha: 1), lines: 1)
            let chinese = Self.label(row.text, font: Self.textFont,
                                     color: selected ? .white : NSColor(white: 0.12, alpha: 1), lines: lines)
            let gloss = Self.label(row.translationText, font: Self.annotationFont,
                                   color: selected ? .white : NSColor(white: 0.38, alpha: 1), lines: lines)
            let textX = padding / 2 + indexWidth + gap
            let contentHeight = max(0, height - 8)
            number.frame = NSRect(x: padding / 2, y: 6, width: indexWidth, height: max(0, height - 10))
            chinese.frame = NSRect(x: textX, y: 4, width: textWidth, height: contentHeight)
            gloss.frame = NSRect(x: textX + textWidth + gap, y: 4, width: glossWidth, height: contentHeight)
            for label in [number, chinese, gloss] {
                // Expose one complete candidate row to VoiceOver, including untruncated text.
                label.setAccessibilityElement(false)
                rowView.addSubview(label)
            }
            rowView.setAccessibilityChildren([])
            addSubview(rowView)
            accessibleRows.append(rowView)
            y += height
        }
        var footerText = footer
        if !visible.isEmpty, visible.count < rows.count {
            footerText += " · \(visible.lowerBound + 1)–\(visible.upperBound)/\(rows.count) 项 · ↑↓ 查看"
        }
        let footerLabel = Self.label(footerText, font: Self.indexFont, color: NSColor(white: 0.4, alpha: 1), lines: 1)
        footerLabel.alignment = .right
        footerLabel.frame = NSRect(x: padding, y: padding + headerHeight + bodyHeight + 4, width: contentWidth, height: max(0, footerHeight - 8))
        footerLabel.setAccessibilityLabel(footerText)
        addSubview(footerLabel)
        setAccessibilityChildren([header] + accessibleRows + [footerLabel])
        setAccessibilitySelectedChildren(accessibleRows.filter { $0.isAccessibilitySelected() })
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private static func label(_ text: String, font: NSFont, color: NSColor, lines: Int) -> NSTextField {
        let field = lines == 1 ? NSTextField(labelWithString: text) : NSTextField(wrappingLabelWithString: text)
        field.font = font
        field.textColor = color
        field.maximumNumberOfLines = lines
        field.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        field.cell?.truncatesLastVisibleLine = true
        field.setAccessibilityRole(.staticText)
        return field
    }

    private static func lineHeight(_ font: NSFont) -> CGFloat {
        ceil(NSLayoutManager().defaultLineHeight(for: font))
    }

    private static func height(_ text: String, font: NSFont, width: CGFloat, lines: Int) -> CGFloat {
        let lineHeight = lineHeight(font)
        guard lines > 1, !text.isEmpty else { return lineHeight }
        let measured = (text as NSString).boundingRect(with: NSSize(width: max(1, width - 4), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        // NSTextField cells need a small vertical inset beyond the glyph bounds.
        return min(lineHeight * CGFloat(lines), max(lineHeight, ceil(measured.height))) + 4
    }

    private static func visibleRows(heights: [CGFloat], highlighted: Int, availableHeight: CGFloat) -> Range<Int> {
        guard !heights.isEmpty, availableHeight > 0 else { return 0..<0 }
        guard heights.reduce(0, +) > availableHeight else { return 0..<heights.count }
        let selected = min(max(0, highlighted), heights.count - 1)
        var lower = selected
        var upper = selected + 1
        var height = min(heights[selected], availableHeight)
        while lower > 0, height + heights[lower - 1] <= availableHeight {
            lower -= 1
            height += heights[lower]
        }
        while upper < heights.count, height + heights[upper] <= availableHeight {
            height += heights[upper]
            upper += 1
        }
        return lower..<upper
    }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        NSColor(white: 0.78, alpha: 1).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
    }
}

@MainActor
private final class CandidateRowView: NSView {
    private let selected: Bool
    override var isFlipped: Bool { true }
    init(selected: Bool) { self.selected = selected; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func draw(_ dirtyRect: NSRect) {
        if selected {
            NSColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
    }
}
