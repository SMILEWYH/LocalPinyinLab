import AppKit
import PinyinCore
import PinyinApplication

@MainActor
public final class CandidatePanel: CandidatePresenting {
    private let anchor: () -> NSRect
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

    public init(anchor: @escaping () -> NSRect = { .zero }) {
        self.anchor = anchor
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.level = NSWindow.Level(rawValue: 101)
    }

    public func show(rows: [CandidateRow], pinyin: String, selected: Int, page: Int, totalPages: Int, anchor: NSRect, status: String? = nil) {
        let view = CandidateView(rows: rows, pinyin: pinyin, highlighted: selected, footer: status ?? "\(page + 1)/\(totalPages)")
        let size = view.preferredSize
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        let below = anchor.minY - 4 - size.height
        let y = below >= bounds.minY ? below : anchor.maxY + 4
        let origin = NSPoint(x: min(max(anchor.minX, bounds.minX), max(bounds.minX, bounds.maxX - size.width)),
                             y: min(max(y, bounds.minY), max(bounds.minY, bounds.maxY - size.height)))
        panel.contentView = view
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    public func show(_ presentation: CandidatePresentation) {
        var rectangle = anchor()
        if rectangle == .zero { rectangle = NSRect(origin: NSEvent.mouseLocation, size: NSSize(width: 0, height: 16)) }
        show(rows: presentation.rows, pinyin: presentation.markedText, selected: presentation.highlighted,
             page: presentation.page, totalPages: presentation.totalPages, anchor: rectangle, status: presentation.status)
    }

    public func hide() { panel.orderOut(nil) }

    public func showLoading(pinyin: String) {
        guard panel.isVisible, let contentView = panel.contentView else { return }
        // Keep the window in place, but never present stale candidates as selectable.
        let view = CandidateView(rows: [], pinyin: pinyin, highlighted: -1, footer: "查询中…")
        view.setFrameSize(contentView.bounds.size)
        panel.contentView = view
    }
}
