import AppKit
import PinyinCore
import PinyinApplication

@MainActor
public final class CandidatePanel: CandidatePresenting {
    private let anchor: () -> NSRect
    private let windowLevel: () -> Int
    private let touchBar: (any CandidateTouchBarDisplaying)?
    private let touchBarOwner = UUID()
    private var statusTask: Task<Void, Never>?
    private var statusID: UUID?
    private var recoveryTask: Task<Void, Never>?
    private var presentationID: UUID?
    private let panelFactory: () -> NSPanel
    private let foregroundPID: () -> pid_t?
    private let diagnosticOwner: String
    private lazy var diagnostics = CandidateWindowDiagnostics(panel: panel, owner: diagnosticOwner)
    package private(set) var panel: NSPanel

    public convenience init(anchor: @escaping () -> NSRect = { .zero }, windowLevel: @escaping () -> Int = { 0 },
                            touchBar: (any CandidateTouchBarDisplaying)? = nil,
                            diagnosticOwner: String = UUID().uuidString) {
        self.init(anchor: anchor, windowLevel: windowLevel, touchBar: touchBar, diagnosticOwner: diagnosticOwner,
                  panelFactory: { NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false) },
                  foregroundPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier })
    }

    package init(anchor: @escaping () -> NSRect = { .zero }, windowLevel: @escaping () -> Int = { 0 },
                 touchBar: (any CandidateTouchBarDisplaying)? = nil,
                 diagnosticOwner: String = UUID().uuidString, panelFactory: @escaping () -> NSPanel,
                 foregroundPID: @escaping () -> pid_t?) {
        self.anchor = anchor
        self.windowLevel = windowLevel
        self.touchBar = touchBar
        self.diagnosticOwner = diagnosticOwner
        self.panelFactory = panelFactory
        self.foregroundPID = foregroundPID
        panel = panelFactory()
        configurePanel()
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]
        updateWindowLevel()
    }

    isolated deinit {
        statusTask?.cancel()
        recoveryTask?.cancel()
        touchBar?.hide(owner: touchBarOwner)
    }

    public func show(rows: [CandidateRow], pinyin: String, selected: Int, page: Int, totalPages: Int, anchor: NSRect, status: String? = nil,
                     translationLanguage: TranslationLanguage = .english) {
        cancelStatus()
        let pageText = "\(translationLanguage.displayName)译文 · 第 \(page + 1)/\(max(1, totalPages)) 页"
        let footer = status.map { pageText + " · " + $0 } ?? pageText
        let bounds = visibleBounds(at: anchor)
        let view = CandidateView(rows: rows, pinyin: pinyin, highlighted: selected, footer: footer, maximumSize: bounds.size,
                                 translationLanguage: translationLanguage)
        let previousSelection = (panel.contentView?.accessibilitySelectedChildren()?.first as? NSView)?.accessibilityLabel()
        display(view, size: view.preferredSize, anchor: anchor)
        if rows.indices.contains(selected) {
            touchBar?.show(owner: touchBarOwner, row: rows[selected], language: translationLanguage)
        } else {
            touchBar?.hide(owner: touchBarOwner)
        }
        NSAccessibility.post(element: panel, notification: .layoutChanged)
        let selection = (view.accessibilitySelectedChildren()?.first as? NSView)?.accessibilityLabel()
        if selection != previousSelection { NSAccessibility.post(element: view, notification: .selectedChildrenChanged) }
    }

    private func visibleBounds(at anchor: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        return frame.insetBy(dx: min(8, frame.width / 4), dy: min(8, frame.height / 4))
    }

    private func display(_ view: NSView, size: NSSize, anchor: NSRect, isStatus: Bool = false) {
        recoveryTask?.cancel()
        let identifier = UUID()
        presentationID = identifier
        updateWindowLevel()
        let bounds = visibleBounds(at: anchor)
        let size = NSSize(width: min(size.width, bounds.width), height: min(size.height, bounds.height))
        let below = anchor.minY - 4 - size.height
        let y = below >= bounds.minY ? below : anchor.maxY + 4
        let preferred = isStatus ? statusOrigin(size: size, anchor: anchor, bounds: bounds) : NSPoint(x: anchor.minX, y: y)
        let origin = NSPoint(x: min(max(preferred.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width)),
                             y: min(max(preferred.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height)))
        panel.contentView = view
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        diagnostics.willShow()
        panel.orderFrontRegardless()
        diagnostics.didShow()
        scheduleWindowRecovery(for: identifier)
    }

    private func scheduleWindowRecovery(for identifier: UUID) {
        let expectedPanel = panel
        guard let expectedPID = foregroundPID() else { return }
        recoveryTask = Task { [weak self, weak expectedPanel] in
            // WindowServer can remove a sticky panel from every Space during
            // Space destruction. AppKit initially reports it as visible; wait
            // for its Space state to settle before checking the association.
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return }
            guard !Task.isCancelled, let self, let expectedPanel,
                  self.presentationID == identifier, self.panel === expectedPanel,
                  self.foregroundPID() == expectedPID, !expectedPanel.isOnActiveSpace else { return }
            self.recoveryTask = nil
            self.rebuildWindow()
        }
    }

    private func rebuildWindow() {
        let previous = panel
        let view = previous.contentView
        let frame = previous.frame
        let level = previous.level
        diagnostics.willRebuild()
        diagnostics.willHide()
        previous.orderOut(nil)
        previous.contentView = nil
        panel = panelFactory()
        configurePanel()
        panel.level = level
        panel.contentView = view
        panel.setFrame(frame, display: true)
        diagnostics = CandidateWindowDiagnostics(panel: panel, owner: diagnosticOwner)
        diagnostics.willShow()
        panel.orderFrontRegardless()
        diagnostics.didShow()
        NSAccessibility.post(element: panel, notification: .layoutChanged)
        // Do not schedule another recovery here. Each presentation gets one
        // attempt, and hiding or a newer presentation invalidates the old one.
    }

    package func updateWindowLevel() {
        // IMK clients can live in floating or full-screen windows. Follow their
        // current level on every presentation without activating the input service.
        let clientLevel = min(windowLevel(), Int(Int32.max) - 1)
        panel.level = NSWindow.Level(rawValue: max(Int(CGWindowLevelForKey(.popUpMenuWindow)), clientLevel + 1))
    }

    private func statusOrigin(size: NSSize, anchor: NSRect, bounds: NSRect) -> NSPoint {
        let gap: CGFloat = 8
        // AppKit screen coordinates increase upwards. Leave the area below for system hints.
        let above = anchor.maxY + gap
        if above + size.height <= bounds.maxY {
            return NSPoint(x: anchor.minX, y: above)
        }
        let sideY = anchor.midY - size.height / 2
        let right = anchor.maxX + gap
        if right >= bounds.minX, right + size.width <= bounds.maxX {
            return NSPoint(x: right, y: sideY)
        }
        let left = anchor.minX - gap - size.width
        if left >= bounds.minX, left + size.width <= bounds.maxX {
            return NSPoint(x: left, y: sideY)
        }
        // On very narrow displays, use the farther edge and avoid the caret vertically if possible.
        let moreRoomOnRight = bounds.maxX - anchor.maxX >= anchor.minX - bounds.minX
        let below = anchor.minY - gap - size.height
        return NSPoint(x: moreRoomOnRight ? bounds.maxX - size.width : bounds.minX,
                       y: below >= bounds.minY ? below : sideY)
    }

    public func show(_ presentation: CandidatePresentation) {
        show(rows: presentation.rows, pinyin: presentation.markedText, selected: presentation.highlighted,
             page: presentation.page, totalPages: presentation.totalPages, anchor: resolvedAnchor(), status: presentation.status,
             translationLanguage: presentation.translationLanguage)
    }

    public func showCaseStatus(uppercaseLocked: Bool) {
        showStatus(InputStatusView(uppercaseLocked: uppercaseLocked))
    }

    public func showModeStatus(mode: InputMode) {
        showStatus(InputStatusView(mode: mode))
    }

    private func showStatus(_ view: InputStatusView) {
        cancelStatus()
        touchBar?.hide(owner: touchBarOwner)
        display(view, size: view.preferredSize, anchor: resolvedAnchor(), isStatus: true)
        NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
            .announcement: view.message, .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
        let identifier = UUID()
        statusID = identifier
        statusTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) }
            catch { return }
            guard !Task.isCancelled, let self, self.statusID == identifier else { return }
            self.hide()
        }
    }

    public func hide() {
        cancelStatus()
        touchBar?.hide(owner: touchBarOwner)
        presentationID = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        diagnostics.willHide()
        panel.orderOut(nil)
        diagnostics.didHide()
    }

    public func showLoading(pinyin: String) {
        cancelStatus()
        touchBar?.hide(owner: touchBarOwner)
        // Keep the window in place, but never present stale candidates as selectable.
        let anchor = resolvedAnchor()
        let previousHeight = panel.isVisible ? (panel.contentView as? CandidateView)?.bounds.height ?? 80 : 80
        let view = CandidateView(rows: [], pinyin: pinyin, highlighted: -1, footer: "查询中…",
                                 maximumSize: visibleBounds(at: anchor).size, minimumHeight: previousHeight)
        display(view, size: view.preferredSize, anchor: anchor)
        NSAccessibility.post(element: panel, notification: .layoutChanged)
    }

    private func resolvedAnchor() -> NSRect {
        let rectangle = anchor()
        return rectangle == .zero ? NSRect(origin: NSEvent.mouseLocation, size: NSSize(width: 0, height: 16)) : rectangle
    }

    private func cancelStatus() {
        statusTask?.cancel()
        statusTask = nil
        statusID = nil
    }
}
