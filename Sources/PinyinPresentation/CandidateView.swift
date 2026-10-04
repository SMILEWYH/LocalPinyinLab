// Swift adaptation of qingjian's AppKit vertical layout; see NOTICE and LICENSE.
import AppKit
import PinyinCore

@MainActor
public final class CandidateView: NSView {
    let rows: [CandidateRow]
    let pinyin: String
    let highlighted: Int
    let footer: String
    private let textFont = NSFont.systemFont(ofSize: 16)
    private let annotationFont = NSFont.systemFont(ofSize: 12)
    private let indexFont = NSFont.systemFont(ofSize: 11)
    private let padding: CGFloat = 8
    private let rowPadding: CGFloat = 4
    private let gap: CGFloat = 8

    public override var isFlipped: Bool { true }

    public init(rows: [CandidateRow], pinyin: String, highlighted: Int, footer: String) {
        precondition(rows.count <= PinyinRules.pageSize)
        self.rows = rows
        self.pinyin = pinyin
        self.highlighted = highlighted
        self.footer = footer
        super.init(frame: .zero)
        appearance = NSAppearance(named: .aqua)
        setFrameSize(preferredSize)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private func size(_ text: String, _ font: NSFont) -> NSSize {
        (text as NSString).size(withAttributes: [.font: font])
    }

    private var indexWidth: CGFloat { size("9", indexFont).width }
    private var textWidth: CGFloat { rows.map { size($0.text, textFont).width }.max() ?? 0 }
    private var rowHeight: CGFloat { size("中文", textFont).height + rowPadding * 2 }
    private var topHeight: CGFloat { size("x", annotationFont).height + rowPadding * 2 }

    public var preferredSize: NSSize {
        let gloss = rows.map { size($0.translationText, annotationFont).width }.max() ?? 0
        let bodyWidth = indexWidth + gap + textWidth + gap + gloss
        return NSSize(width: max(bodyWidth, size(pinyin, annotationFont).width, size(footer, indexFont).width) + padding * 2,
                      height: padding * 2 + topHeight + rowHeight * CGFloat(rows.count)
                        + size(footer, indexFont).height + rowPadding)
    }

    private func drawText(_ text: String, font: NSFont, color: NSColor, x: CGFloat, y: CGFloat) {
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
    }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        NSColor(white: 0.78, alpha: 1).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
        drawText(pinyin + "│", font: annotationFont, color: NSColor(white: 0.38, alpha: 1), x: padding, y: padding + rowPadding)
        let textX = padding + indexWidth + gap
        let glossX = textX + textWidth + gap
        let smallOffset = max(0, size("中文", textFont).height - size("x", annotationFont).height)
        var y = padding + topHeight
        for (index, row) in rows.enumerated() {
            let selected = index == highlighted
            if selected {
                NSColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: padding / 2, y: y, width: bounds.width - padding, height: rowHeight), xRadius: 4, yRadius: 4).fill()
            }
            drawText(String(index + 1), font: indexFont, color: selected ? .white : NSColor(white: 0.45, alpha: 1), x: padding, y: y + rowPadding + smallOffset)
            drawText(row.text, font: textFont, color: selected ? .white : NSColor(white: 0.12, alpha: 1), x: textX, y: y + rowPadding)
            drawText(row.translationText, font: annotationFont, color: selected ? .white : NSColor(white: 0.38, alpha: 1), x: glossX, y: y + rowPadding + smallOffset)
            y += rowHeight
        }
        drawText(footer, font: indexFont, color: NSColor(white: 0.4, alpha: 1), x: bounds.width - padding - size(footer, indexFont).width, y: y + rowPadding)
    }
}
