// Swift adaptation of qingjian's AppKit vertical layout; see NOTICE and LICENSE.
import AppKit
import PinyinCore

@MainActor
public final class CandidateView: NSView {
    private static let textFont = NSFont.systemFont(ofSize: 16)
    private static let annotationFont = NSFont.systemFont(ofSize: 12)
    private static let partOfSpeechFont = NSFont.systemFont(ofSize: 11)
    private static let indexFont = NSFont.systemFont(ofSize: 11)
    private static let padding: CGFloat = 8
    private static let indexGap: CGFloat = 8
    private static let columnGap: CGFloat = 40
    private static let partOfSpeechGap: CGFloat = 6
    private static let maximumWidth: CGFloat = 600
    private static var lineHeights: [NSFont: CGFloat] = [:]
    private var size: NSSize
    private let rowHeights: [CGFloat]
    private let availableBodyHeight: CGFloat
    private let visible: Range<Int>
    private let footer: String
    private let rowCount: Int
    private var displayedRows: [CandidateRowView] = []
    private var footerLabel: NSTextField!
    package private(set) var highlighted: Int

    public override var isFlipped: Bool { true }
    public var preferredSize: NSSize { size }

    public convenience init(rows: [CandidateRow], pinyin: String, highlighted: Int, footer: String,
                maximumSize: NSSize = NSSize(width: 600, height: 700), minimumHeight: CGFloat = 0, minimumWidth: CGFloat = 0,
                translationLanguage: TranslationLanguage = .english) {
        self.init(rows: rows, pinyin: pinyin, highlighted: highlighted, footer: footer,
                  maximumSize: maximumSize, minimumHeight: minimumHeight, minimumWidth: minimumWidth,
                  translationLanguage: translationLanguage, annotations: Array(repeating: nil, count: rows.count))
    }

    package init(rows: [CandidateRow], pinyin: String, highlighted: Int, footer: String,
                 maximumSize: NSSize = NSSize(width: 600, height: 700), minimumHeight: CGFloat = 0, minimumWidth: CGFloat = 0,
                 translationLanguage: TranslationLanguage = .english, annotations: [TranslationPartOfSpeech?]) {
        precondition(rows.count <= PinyinRules.pageSize)
        precondition(annotations.count == rows.count)
        self.highlighted = highlighted
        self.footer = footer
        rowCount = rows.count
        let widthLimit = max(1, min(Self.maximumWidth, maximumSize.width))
        let textNaturalWidth = rows.map { Self.width($0.text, font: Self.textFont) }.max() ?? 0
        let glossNaturalWidth = rows.map { Self.width($0.translationText(for: translationLanguage), font: Self.annotationFont) }.max() ?? 0
        let partsOfSpeech = annotations
        let partOfSpeechNaturalWidth = partsOfSpeech.compactMap { $0 }.map {
            Self.width($0.abbreviation, font: Self.partOfSpeechFont)
        }.max() ?? 0
        let annotationNaturalWidth = glossNaturalWidth + partOfSpeechNaturalWidth
            + (partOfSpeechNaturalWidth > 0 ? Self.partOfSpeechGap : 0)
        let rowNaturalWidth = rows.isEmpty ? 0 : 12 + Self.indexGap + textNaturalWidth + Self.columnGap + annotationNaturalWidth
        let naturalWidth = max(rowNaturalWidth, Self.width(pinyin + "│", font: Self.annotationFont),
                               Self.width(footer, font: Self.indexFont)) + Self.padding * 2
        let width = min(max(naturalWidth, minimumWidth), widthLimit)
        let maximumHeight = max(1, maximumSize.height)
        let padding = min(Self.padding, width / 12, maximumHeight / 12)
        let contentWidth = max(0, width - padding * 2)
        let indexWidth = min(CGFloat(12), contentWidth / 6)
        let indexGap = min(Self.indexGap, contentWidth / 12)
        // Only a screen too narrow for the fixed chrome can reduce the 40-point gap.
        let columnGap = min(Self.columnGap, max(0, contentWidth - indexWidth - indexGap - 2))
        let columnsWidth = max(0, contentWidth - indexWidth - indexGap - columnGap)
        // Keep short columns at natural width. Share constrained space when both
        // are long, giving any unused translation space back to Chinese text.
        var textWidth = min(textNaturalWidth, floor(columnsWidth * 0.46))
        let annotationWidth = min(annotationNaturalWidth, columnsWidth - textWidth)
        textWidth = min(textNaturalWidth, columnsWidth - annotationWidth)
        // Reserve a shared POS column even for untagged rows, so all translations
        // align. On extremely narrow screens keep at least some translation room.
        let partOfSpeechWidth = min(partOfSpeechNaturalWidth, max(0, annotationWidth - min(12, glossNaturalWidth)))
        let partOfSpeechGap = partOfSpeechWidth > 0
            ? min(Self.partOfSpeechGap, max(0, annotationWidth - partOfSpeechWidth - 1)) : 0
        let glossWidth = max(0, annotationWidth - partOfSpeechWidth - partOfSpeechGap)
        let headerHeight = min(Self.height(pinyin + "│", font: Self.annotationFont, width: contentWidth) + 8,
                               maximumHeight / 3)
        let footerHeight = min(Self.lineHeight(Self.indexFont) + 8, maximumHeight / 4)
        let availableBodyHeight = max(0, maximumHeight - padding * 2 - headerHeight - footerHeight)
        let rowHeights = rows.map { row in
            max(Self.height(row.text, font: Self.textFont, width: textWidth),
                Self.height(row.translationText(for: translationLanguage), font: Self.annotationFont, width: glossWidth)) + 8
        }
        let visible = Self.visibleRows(heights: rowHeights, highlighted: highlighted, availableHeight: availableBodyHeight)
        let minimumBodyHeight = rows.isEmpty ? max(0, minimumHeight - padding * 2 - headerHeight - footerHeight) : 0
        let bodyHeight = min(max(minimumBodyHeight, visible.reduce(CGFloat.zero) { $0 + rowHeights[$1] }), availableBodyHeight)
        size = NSSize(width: width, height: min(maximumHeight, padding * 2 + headerHeight + bodyHeight + footerHeight))
        self.rowHeights = rowHeights
        self.availableBodyHeight = availableBodyHeight
        self.visible = visible
        super.init(frame: NSRect(origin: .zero, size: size))
        appearance = NSAppearance(named: .aqua)
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel(rows.isEmpty ? "拼音候选，查询中" : "拼音候选")
        setAccessibilityValue(pinyin + "，" + footer)
        setAccessibilityHelp("上下方向键选择，空格确认，数字键选词，左右方向键翻页。")

        let header = Self.label(pinyin + "│", font: Self.annotationFont, color: NSColor(white: 0.38, alpha: 1), lines: 0)
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
            rowView.setAccessibilityLabel(row.accessibilityText(index: index, language: translationLanguage, annotation: annotations[index]))
            rowView.setAccessibilitySelected(selected)
            rowView.setAccessibilityIndex(index)
            let number = Self.label(String(index + 1), font: Self.indexFont,
                                    color: selected ? .white : NSColor(white: 0.45, alpha: 1), lines: 1)
            let chinese = Self.label(row.text, font: Self.textFont,
                                     color: selected ? .white : NSColor(white: 0.12, alpha: 1), lines: 0)
            let gloss = Self.label(row.translationText(for: translationLanguage), font: Self.annotationFont,
                                   color: selected ? .white : NSColor(white: 0.38, alpha: 1), lines: 0)
            let textX = padding / 2 + indexWidth + indexGap
            let contentHeight = max(0, rowHeights[index] - 8)
            number.frame = NSRect(x: padding / 2, y: 6, width: indexWidth, height: max(0, height - 10))
            chinese.frame = NSRect(x: textX, y: 4, width: textWidth, height: contentHeight)
            let annotationX = textX + textWidth + columnGap
            gloss.frame = NSRect(x: annotationX + partOfSpeechWidth + partOfSpeechGap, y: 4, width: glossWidth, height: contentHeight)
            var labels = [number, chinese, gloss]
            for label in labels {
                // Expose one complete candidate row to VoiceOver, including untruncated text.
                label.setAccessibilityElement(false)
                rowView.addSubview(label)
            }
            if let partOfSpeech = partsOfSpeech[index] {
                let label = Self.label(partOfSpeech.abbreviation, font: Self.partOfSpeechFont,
                                       color: selected ? NSColor.white.withAlphaComponent(0.78) : NSColor(white: 0.52, alpha: 1), lines: 1)
                label.frame = NSRect(x: annotationX, y: 5, width: partOfSpeechWidth, height: max(0, contentHeight - 1))
                label.setAccessibilityElement(false)
                rowView.addSubview(label)
                labels.append(label)
            }
            rowView.configure(labels: labels, naturalHeight: rowHeights[index])
            rowView.setAccessibilityChildren([])
            addSubview(rowView)
            accessibleRows.append(rowView)
            displayedRows.append(rowView)
            y += height
        }
        let footerText = currentFooter
        // Fit the navigation hint added for short screens without stretching columns.
        let footerWidth = min(widthLimit, Self.width(footerText, font: Self.indexFont) + padding * 2)
        if footerWidth > size.width {
            size.width = footerWidth
            setFrameSize(size)
            header.frame.size.width = size.width - padding * 2
            for row in accessibleRows { row.frame.size.width = size.width - padding }
        }
        footerLabel = Self.label(footerText, font: Self.indexFont, color: NSColor(white: 0.4, alpha: 1), lines: 1)
        footerLabel.alignment = .right
        footerLabel.frame = NSRect(x: padding, y: padding + headerHeight + bodyHeight + 4, width: size.width - padding * 2, height: max(0, footerHeight - 8))
        footerLabel.setAccessibilityLabel(footerText)
        addSubview(footerLabel)
        setAccessibilityChildren([header] + accessibleRows + [footerLabel!])
        setAccessibilitySelectedChildren(accessibleRows.filter { $0.isAccessibilitySelected() })
    }

    /// Selection-only changes reuse all cells and measurements while their visible range is stable.
    package func updateHighlighted(_ index: Int) -> Bool {
        guard Self.visibleRows(heights: rowHeights, highlighted: index, availableHeight: availableBodyHeight) == visible else { return false }
        highlighted = index
        for row in displayedRows { row.updateSelected(row.accessibilityIndex() == index) }
        setAccessibilitySelectedChildren(displayedRows.filter { $0.isAccessibilitySelected() })
        if footerLabel.stringValue != currentFooter { updateFooter() }
        return true
    }

    package var highlightedScrollProgress: CGFloat {
        displayedRows.first { $0.isAccessibilitySelected() }?.scrollProgress ?? 0
    }

    package func restoreHighlightedScrollProgress(_ progress: CGFloat) {
        displayedRows.first { $0.isAccessibilitySelected() }?.restoreScrollProgress(progress)
        updateFooter()
    }

    package func scrollHighlightedCandidate(by pages: Int) -> Bool {
        guard let row = displayedRows.first(where: { $0.isAccessibilitySelected() }), row.scroll(by: pages) else { return false }
        updateFooter()
        NSAccessibility.post(element: row, notification: .valueChanged)
        return true
    }

    private var currentFooter: String {
        var text = footer
        if !visible.isEmpty, visible.count < rowCount {
            text += " · \(visible.lowerBound + 1)–\(visible.upperBound)/\(rowCount) 项 · ↑↓ 查看"
        }
        if let hint = displayedRows.first(where: { $0.isAccessibilitySelected() })?.scrollHint {
            // Lead with the action so a narrow display cannot truncate the way to read more.
            text = hint + " · " + text
        }
        return text
    }

    private func updateFooter() {
        footerLabel.stringValue = currentFooter
        footerLabel.setAccessibilityLabel(currentFooter)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private static func label(_ text: String, font: NSFont, color: NSColor, lines: Int) -> NSTextField {
        let field = lines == 1 ? NSTextField(labelWithString: text) : NSTextField(wrappingLabelWithString: text)
        field.font = font
        field.alignment = .left
        field.baseWritingDirection = .natural
        field.textColor = color
        field.maximumNumberOfLines = lines
        field.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        field.cell?.truncatesLastVisibleLine = lines == 1
        field.setAccessibilityRole(.staticText)
        return field
    }

    private static func lineHeight(_ font: NSFont) -> CGFloat {
        if let height = lineHeights[font] { return height }
        let height = ceil(NSLayoutManager().defaultLineHeight(for: font))
        lineHeights[font] = height
        return height
    }

    private static func width(_ text: String, font: NSFont) -> CGFloat {
        let field = label(text, font: font, color: .labelColor, lines: 0)
        return max(1, ceil(field.cell?.cellSize.width ?? 0))
    }

    private static func height(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        // Measure the same wrapping cell used to draw, including explicit line
        // breaks and long tokens. Glyph bounds alone can undercount wrapped lines.
        let field = label(text, font: font, color: .labelColor, lines: 0)
        let bounds = NSRect(x: 0, y: 0, width: max(1, width), height: .greatestFiniteMagnitude)
        let measured = field.cell?.cellSize(forBounds: bounds).height ?? lineHeight(font)
        return max(lineHeight(font), ceil(measured))
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
    private var selected: Bool
    private var labels: [NSTextField] = []
    private var viewport: NSClipView?
    private var scrollPage = 0
    override var isFlipped: Bool { true }
    init(selected: Bool) { self.selected = selected; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func configure(labels: [NSTextField], naturalHeight: CGFloat) {
        self.labels = labels
        guard naturalHeight > frame.height, frame.height > 8 else { return }
        let clip = NSClipView(frame: NSRect(x: 0, y: 4, width: bounds.width, height: bounds.height - 8))
        clip.drawsBackground = false
        clip.autoresizingMask = [.width]
        clip.setAccessibilityElement(false)
        let document = CandidateRowDocument(frame: NSRect(x: 0, y: 0, width: bounds.width, height: naturalHeight - 8))
        document.setAccessibilityElement(false)
        for label in labels.dropFirst() {
            label.removeFromSuperview()
            label.frame.origin.y -= 4
            document.addSubview(label)
        }
        clip.documentView = document
        addSubview(clip)
        viewport = clip
        setAccessibilityHelp("本项内容超过窗口高度，Shift + Page Up / Page Down 查看全文。")
    }

    func updateSelected(_ value: Bool) {
        guard value != selected else { return }
        selected = value
        setAccessibilitySelected(value)
        let normal: [NSColor] = [NSColor(white: 0.45, alpha: 1), NSColor(white: 0.12, alpha: 1),
                                 NSColor(white: 0.38, alpha: 1), NSColor(white: 0.52, alpha: 1)]
        for (index, label) in labels.enumerated() {
            label.textColor = value ? (index == 3 ? .white.withAlphaComponent(0.78) : .white) : normal[index]
        }
        needsDisplay = true
    }

    private var maximumOffset: CGFloat {
        guard let viewport, let document = viewport.documentView else { return 0 }
        return max(0, document.frame.height - viewport.bounds.height)
    }
    private var pageHeight: CGFloat { max(1, (viewport?.bounds.height ?? 0) * 0.85) }
    private var lastPage: Int { Int(ceil(maximumOffset / pageHeight)) }
    var scrollHint: String? {
        guard maximumOffset > 0 else { return nil }
        return "全文 \(scrollPage + 1)/\(lastPage + 1) · ⇧PageUp/Down"
    }
    var scrollProgress: CGFloat {
        guard maximumOffset > 0 else { return 0 }
        return (viewport?.bounds.minY ?? 0) / maximumOffset
    }

    func restoreScrollProgress(_ progress: CGFloat) {
        guard maximumOffset > 0 else { return }
        scrollPage = Int((min(1, max(0, progress)) * CGFloat(lastPage)).rounded())
        applyScroll()
    }

    func scroll(by pages: Int) -> Bool {
        guard maximumOffset > 0, pages != 0 else { return false }
        let (target, overflow) = scrollPage.addingReportingOverflow(pages)
        scrollPage = overflow ? (pages > 0 ? lastPage : 0) : min(lastPage, max(0, target))
        applyScroll()
        // Keep consuming at the ends: a further scroll must not select another candidate page.
        return true
    }

    private func applyScroll() {
        viewport?.scroll(to: NSPoint(x: 0, y: min(maximumOffset, CGFloat(scrollPage) * pageHeight)))
        setAccessibilityValue(scrollHint)
    }

    override func draw(_ dirtyRect: NSRect) {
        if selected {
            NSColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
    }
}

@MainActor
private final class CandidateRowDocument: NSView {
    override var isFlipped: Bool { true }
}
