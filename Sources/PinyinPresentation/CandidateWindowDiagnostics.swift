import AppKit
import Combine
import OSLog

/// Window metadata only: never inspect the content view or the client's document.
@MainActor
final class CandidateWindowDiagnostics {
    private static let logger = Logger(subsystem: "local.pinyinlab.inputmethod", category: "CandidateWindow")
    private weak var panel: NSPanel?
    private let owner: String
    private var wantsVisible = false
    private var sequence: UInt64 = 0
    private var previousState: String?
    private var previousOnscreen: String?
    private var settledTask: Task<Void, Never>?
    private var observations: [AnyCancellable] = []

    init(panel: NSPanel, owner: String) {
        self.panel = panel
        self.owner = owner
        observe(NotificationCenter.default, name: NSWindow.didChangeOcclusionStateNotification, object: panel, event: "occlusion")
        observe(NotificationCenter.default, name: NSWindow.didChangeScreenNotification, object: panel, event: "screen")
        observe(NSWorkspace.shared.notificationCenter, name: NSWorkspace.activeSpaceDidChangeNotification, event: "space")
    }

    deinit { settledTask?.cancel() }

    func willShow() {
        guard !wantsVisible else { return }
        wantsVisible = true
        record("show-request", force: true)
    }

    func didShow() {
        record("ordered")
        settledTask?.cancel()
        settledTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return }
            guard !Task.isCancelled, let self, self.wantsVisible else { return }
            self.record("settled", probeWindowServer: true)
        }
    }

    func willHide() {
        settledTask?.cancel()
        settledTask = nil
        guard wantsVisible else { return }
        wantsVisible = false
        record("hide-request", force: true)
    }

    func didHide() { record("hidden") }

    func willRebuild() { record("rebuild-space", force: true, probeWindowServer: true) }

    private func observe(_ center: NotificationCenter, name: Notification.Name, object: AnyObject? = nil, event: String) {
        observations.append(center.publisher(for: name, object: object).sink { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.wantsVisible || self.panel?.isVisible == true else { return }
                self.record(event, force: true, probeWindowServer: true)
            }
        })
    }

    private func record(_ event: String, force: Bool = false, probeWindowServer: Bool = false) {
        guard let panel else { return }
        var onscreen: String?
        if probeWindowServer {
            // Keep WindowServer round trips off the per-keystroke rendering path.
            // Query this window alone; do not collect other applications' titles.
            let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(panel.windowNumber)) as? [[String: Any]]
            onscreen = (windows?.first?[kCGWindowIsOnscreen as String] as? Bool).map { $0 ? "1" : "0" } ?? "unknown"
        }
        let state = "window=\(panel.windowNumber) intent=\(wantsVisible) visible=\(panel.isVisible) "
            + "activeSpace=\(panel.isOnActiveSpace) occlusion=\(panel.occlusionState.rawValue) "
            + "frame=\(NSStringFromRect(panel.frame)) level=\(panel.level.rawValue) behavior=\(panel.collectionBehavior.rawValue) "
            + "appHidden=\(NSApp.isHidden) policy=\(NSApp.activationPolicy().rawValue)"
        guard force || previousState != state || (onscreen != nil && onscreen != previousOnscreen) else { return }
        previousState = state
        if let onscreen { previousOnscreen = onscreen }
        sequence &+= 1
        Self.logger.notice("owner=\(self.owner, privacy: .public) sequence=\(self.sequence) event=\(event, privacy: .public) \(state, privacy: .public) onscreen=\(onscreen ?? "not-sampled", privacy: .public)")
    }
}
