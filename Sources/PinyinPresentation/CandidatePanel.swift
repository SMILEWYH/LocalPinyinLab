import AppKit
import PinyinCore
import PinyinApplication

@MainActor
public final class CandidatePanel: CandidatePresenting {
    private let anchor: () -> NSRect
    private var caseStatusTask: Task<Void, Never>?
    private var caseStatusID: UUID?
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

    deinit { caseStatusTask?.cancel() }

    public func show(rows: [CandidateRow], pinyin: String, selected: Int, page: Int, totalPages: Int, anchor: NSRect, status: String? = nil) {
        cancelCaseStatus()
        let view = CandidateView(rows: rows, pinyin: pinyin, highlighted: selected, footer: status ?? "\(page + 1)/\(totalPages)")
        display(view, size: view.preferredSize, anchor: anchor)
    }

    private func display(_ view: NSView, size: NSSize, anchor: NSRect) {
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
        show(rows: presentation.rows, pinyin: presentation.markedText, selected: presentation.highlighted,
             page: presentation.page, totalPages: presentation.totalPages, anchor: resolvedAnchor(), status: presentation.status)
    }

    public func showCaseStatus(uppercaseLocked: Bool) {
        cancelCaseStatus()
        let view = CaseStatusView(uppercaseLocked: uppercaseLocked)
        display(view, size: view.preferredSize, anchor: resolvedAnchor())
        let identifier = UUID()
        caseStatusID = identifier
        caseStatusTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) }
            catch { return }
            guard !Task.isCancelled, let self, self.caseStatusID == identifier else { return }
            self.hide()
        }
    }

    public func hide() {
        cancelCaseStatus()
        panel.orderOut(nil)
    }

    public func showLoading(pinyin: String) {
        guard panel.isVisible, let contentView = panel.contentView as? CandidateView else { return }
        // Keep the window in place, but never present stale candidates as selectable.
        let view = CandidateView(rows: [], pinyin: pinyin, highlighted: -1, footer: "查询中…")
        view.setFrameSize(contentView.bounds.size)
        panel.contentView = view
    }

    private func resolvedAnchor() -> NSRect {
        let rectangle = anchor()
        return rectangle == .zero ? NSRect(origin: NSEvent.mouseLocation, size: NSSize(width: 0, height: 16)) : rectangle
    }

    private func cancelCaseStatus() {
        caseStatusTask?.cancel()
        caseStatusTask = nil
        caseStatusID = nil
    }
}
