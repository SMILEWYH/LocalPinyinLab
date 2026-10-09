import AppKit
import PinyinCore
import PinyinPresentation

extension PresentationChecks {
    /// The panel double never orders a real window onscreen or changes focus.
    @MainActor static func checkCandidateWindowRecovery() async throws {
        try await recoveryPreservesPresentation()
        try await occlusionDoesNotRebuild()
        try await hidingCancelsRecovery()
        try await newerPresentationSupersedesRecovery()
        try await changingForegroundCancelsRecovery()
        try await recoveryDoesNotRepeatItself()
        try await recoveredStatusStillExpires()
        try await updatesReuseVisibleWindow()
    }

    @MainActor private static func updatesReuseVisibleWindow() async throws {
        let fixture = RecoveryFixture(initialSpace: true)
        defer { fixture.presenter.hide() }
        fixture.presenter.showLoading(pinyin: "n")
        let panel = fixture.presenter.panel as! RecoveryPanel
        precondition(panel.isVisible && panel.orderFrontCalls == 1,
                     "the first keystroke must show the candidate window once")
        fixture.showCandidates()
        let candidateSize = panel.frame.size
        fixture.presenter.showLoading(pinyin: "nihaom")
        precondition(panel.frame.size == candidateSize,
                     "querying the next spelling must preserve the candidate window's width and height")
        precondition(panel.contentView?.accessibilityValue() as? String == "nihaom，查询中…" &&
                     panel.contentView?.accessibilitySelectedChildren()?.isEmpty == true,
                     "loading must update the spelling and remove stale selectable candidates")
        fixture.showCandidates()
        fixture.showCandidates()
        try await Task.sleep(for: .milliseconds(300))
        precondition(fixture.environment.panels.count == 1 && fixture.presenter.panel === panel &&
                     panel.isVisible && panel.orderFrontCalls == 1 && panel.orderOutCalls == 0,
                     "typing and candidate updates must reuse the visible window without ordering it again")
        fixture.presenter.hide()
        fixture.presenter.showLoading(pinyin: "h")
        precondition(fixture.presenter.panel === panel && panel.isVisible && panel.orderFrontCalls == 2,
                     "a new composition after hiding must show the existing window again")
    }

    @MainActor private static func recoveryPreservesPresentation() async throws {
        let fixture = RecoveryFixture(initialSpace: false)
        defer { fixture.presenter.hide() }
        fixture.environment.hostLevel = NSWindow.Level.screenSaver.rawValue
        fixture.showCandidates()
        let previous = fixture.environment.panels[0]
        let view = previous.contentView!
        let frame = previous.frame
        let level = previous.level
        let behavior = previous.collectionBehavior
        let accessibilityValue = view.accessibilityValue() as? String
        let selected = (view.accessibilitySelectedChildren()?.first as? NSView)?.accessibilityIndex()

        try await fixture.waitForPanelCount(2)
        let replacement = fixture.environment.panels[1]
        precondition(fixture.presenter.panel === replacement, "recovery must publish the replacement panel")
        precondition(!previous.isVisible && previous.orderOutCalls == 1 && previous.contentView == nil,
                     "the old window must be hidden and release its content view")
        precondition(replacement.contentView === view && replacement.frame == frame && replacement.level == level,
                     "recovery must retain the exact view, position, size and host-aware level")
        precondition(replacement.collectionBehavior == behavior && replacement.styleMask.contains(.nonactivatingPanel),
                     "replacement must retain the configured Space behavior and nonactivating style")
        precondition(!replacement.isOpaque && replacement.backgroundColor == .clear && replacement.hasShadow,
                     "replacement must preserve candidate appearance")
        precondition(!replacement.hidesOnDeactivate && replacement.ignoresMouseEvents,
                     "replacement must not steal interaction from the editor")
        precondition(replacement.isVisible && replacement.orderFrontCalls == 1,
                     "recovery must show its replacement exactly once")
        precondition(!replacement.isKeyWindow && !replacement.isMainWindow,
                     "recovery must never focus the input method")
        precondition(view.accessibilityValue() as? String == accessibilityValue &&
                     (view.accessibilitySelectedChildren()?.first as? NSView)?.accessibilityIndex() == selected,
                     "recovery must preserve marked text, page and candidate selection")
    }

    @MainActor private static func occlusionDoesNotRebuild() async throws {
        let fixture = RecoveryFixture(initialSpace: true)
        defer { fixture.presenter.hide() }
        fixture.showCandidates()
        let panel = fixture.environment.panels[0]
        precondition(panel.occlusionState.isEmpty, "this fixture must simulate a fully occluded window")
        try await Task.sleep(for: .milliseconds(300))
        precondition(fixture.environment.panels.count == 1 && panel.isVisible,
                     "ordinary occlusion on the active Space must not recreate or hide candidates")
    }

    @MainActor private static func hidingCancelsRecovery() async throws {
        let fixture = RecoveryFixture(initialSpace: false)
        fixture.showCandidates()
        fixture.presenter.hide()
        try await Task.sleep(for: .milliseconds(300))
        let panel = fixture.environment.panels[0]
        precondition(fixture.environment.panels.count == 1 && !panel.isVisible && panel.orderFrontCalls == 1,
                     "a cancelled presentation must not be rebuilt or resurrected")
    }

    @MainActor private static func newerPresentationSupersedesRecovery() async throws {
        let fixture = RecoveryFixture(initialSpace: false)
        defer { fixture.presenter.hide() }
        fixture.presenter.showLoading(pinyin: "ni")
        let panel = fixture.environment.panels[0]
        let loading = panel.contentView
        panel.belongsToActiveSpace = true
        fixture.showCandidates()
        let current = panel.contentView
        precondition(current !== loading, "the current presentation must replace the loading view")
        try await Task.sleep(for: .milliseconds(300))
        precondition(fixture.environment.panels.count == 1 && panel.contentView === current && panel.isVisible,
                     "obsolete loading recovery must not replace a healthy newer presentation")
    }

    @MainActor private static func changingForegroundCancelsRecovery() async throws {
        for nextPID: pid_t? in [202, nil] {
            let fixture = RecoveryFixture(initialSpace: false)
            defer { fixture.presenter.hide() }
            fixture.showCandidates()
            fixture.environment.foregroundPID = nextPID
            try await Task.sleep(for: .milliseconds(300))
            precondition(fixture.environment.panels.count == 1,
                         "recovery must not show candidates over a different or missing foreground app")
        }
    }

    @MainActor private static func recoveryDoesNotRepeatItself() async throws {
        let fixture = RecoveryFixture(initialSpace: false, replacementSpace: false)
        defer { fixture.presenter.hide() }
        fixture.showCandidates()
        try await fixture.waitForPanelCount(2)
        try await Task.sleep(for: .milliseconds(350))
        precondition(fixture.environment.panels.count == 2,
                     "a failed replacement must not start an unbounded recovery loop")
        precondition(fixture.environment.panels[1].orderFrontCalls == 1,
                     "one presentation gets one recovery attempt")
    }

    @MainActor private static func recoveredStatusStillExpires() async throws {
        let fixture = RecoveryFixture(initialSpace: false)
        fixture.presenter.showModeStatus(mode: .chinesePinyin)
        try await fixture.waitForPanelCount(2)
        try await Task.sleep(for: .milliseconds(1100))
        precondition(fixture.environment.panels.count == 2 && !fixture.environment.panels[1].isVisible,
                     "the original status timer must hide the replacement instead of leaving a stale popup")
    }
}

@MainActor private final class RecoveryEnvironment {
    var panels: [RecoveryPanel] = []
    var foregroundPID: pid_t? = 101
    var hostLevel = NSWindow.Level.normal.rawValue
}

@MainActor private final class RecoveryFixture {
    let environment: RecoveryEnvironment
    let presenter: CandidatePanel

    init(initialSpace: Bool, replacementSpace: Bool = true) {
        let environment = RecoveryEnvironment()
        self.environment = environment
        presenter = CandidatePanel(windowLevel: { environment.hostLevel }, panelFactory: {
            let panel = RecoveryPanel(onActiveSpace: environment.panels.isEmpty ? initialSpace : replacementSpace)
            environment.panels.append(panel)
            return panel
        }, foregroundPID: { environment.foregroundPID })
    }

    func showCandidates() {
        let rows = [CandidateRow(candidate: Candidate(text: "你", consumedCount: 2)),
                    CandidateRow(candidate: Candidate(text: "你好", consumedCount: 5), translation: .ready("Hello"))]
        presenter.show(rows: rows, pinyin: "nihao", selected: 1, page: 1, totalPages: 3,
                       anchor: NSRect(x: 300, y: 400, width: 1, height: 20))
    }

    func waitForPanelCount(_ count: Int) async throws {
        for _ in 0..<100 where environment.panels.count < count {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(environment.panels.count == count, "Space recovery did not create the expected replacement")
    }
}

@MainActor private final class RecoveryPanel: NSPanel {
    var belongsToActiveSpace: Bool
    private var simulatedVisible = false
    private(set) var orderFrontCalls = 0
    private(set) var orderOutCalls = 0

    init(onActiveSpace: Bool) {
        belongsToActiveSpace = onActiveSpace
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    }

    override var isOnActiveSpace: Bool { belongsToActiveSpace }
    override var isVisible: Bool { simulatedVisible }
    override var occlusionState: NSWindow.OcclusionState { [] }

    override func orderFrontRegardless() {
        orderFrontCalls += 1
        simulatedVisible = true
    }

    override func orderOut(_ sender: Any?) {
        orderOutCalls += 1
        simulatedVisible = false
    }
}
