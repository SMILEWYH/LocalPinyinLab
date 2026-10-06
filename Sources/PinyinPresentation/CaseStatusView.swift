import AppKit

@MainActor
final class CaseStatusView: NSView {
    private let message: String
    private let font = NSFont.systemFont(ofSize: 14, weight: .medium)
    private let horizontalPadding: CGFloat = 12
    private let verticalPadding: CGFloat = 9

    override var isFlipped: Bool { true }

    init(uppercaseLocked: Bool) {
        message = uppercaseLocked ? "ABC · 大写已锁定" : "abc · 已恢复小写"
        super.init(frame: .zero)
        appearance = NSAppearance(named: .aqua)
        setFrameSize(preferredSize)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(message)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    var preferredSize: NSSize {
        let textSize = (message as NSString).size(withAttributes: [.font: font])
        return NSSize(width: ceil(textSize.width) + horizontalPadding * 2,
                      height: ceil(textSize.height) + verticalPadding * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        NSColor(white: 0.78, alpha: 1).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
        (message as NSString).draw(at: NSPoint(x: horizontalPadding, y: verticalPadding),
                                  withAttributes: [.font: font, .foregroundColor: NSColor(white: 0.12, alpha: 1)])
    }
}
