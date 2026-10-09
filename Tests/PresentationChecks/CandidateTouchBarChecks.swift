import AppKit
import PinyinCore
import PinyinPresentation

extension PresentationChecks {
    /// Uses a fake system bridge: no Touch Bar is presented and no focus changes.
    @MainActor static func checkCandidateTouchBarBehavior() async throws {
        touchBarUpdatesReusePresentation()
        touchBarHidingOldOwnerPreservesCurrentOwner()
        touchBarUnavailableBridgeRemainsHarmless()
        touchBarRejectsInvalidEnvironmentBeforePresenting()
        touchBarRejectsChangedForegroundDuringUpdate()
        try await touchBarMonitorClearsSecureInput()
        try await touchBarMonitorClearsChangedForeground()
        try await touchBarCancelledMonitorCannotDismissNewPresentation()
        touchBarLongContentIsBoundedAndAccessible()
    }

    @MainActor private static func touchBarUpdatesReusePresentation() {
        let fixture = TouchBarFixture()
        let owner = UUID()
        defer { fixture.presenter.hide(owner: owner) }
        let candidate = Candidate(text: "你好", consumedCount: 5)
        let pending = CandidateRow(candidate: candidate)
        fixture.presenter.show(owner: owner, row: pending, language: .english)
        precondition(fixture.bridge.presentedBars.count == 1, "the first candidate must present one Touch Bar")
        let bar = fixture.bridge.presentedBars[0]
        precondition(bar.defaultItemIdentifiers.count == 1 && bar.principalItemIdentifier == bar.defaultItemIdentifiers.first,
                     "the selected bilingual candidate must be the centered principal item")
        let item = bar.item(forIdentifier: bar.defaultItemIdentifiers[0]) as? NSCustomTouchBarItem
        precondition(item?.view === fixture.presenter.contentView,
                     "the centered item must use the live candidate content view")
        precondition(fixture.presenter.contentView.chineseLabel.stringValue == candidate.text &&
                     fixture.presenter.contentView.translationLabel.stringValue == pending.translationText(for: .english),
                     "Touch Bar must expose the selected candidate while translation is pending")

        let translated = CandidateRow(candidate: candidate, translation: .ready("Hello"))
        fixture.presenter.show(owner: owner, row: translated, language: .english)
        precondition(fixture.presenter.contentView.translationLabel.stringValue == "Hello",
                     "an asynchronous translation refresh must replace the pending text")
        fixture.presenter.show(owner: owner, row: touchBarRow("再见", "Goodbye"), language: .english)
        precondition(fixture.presenter.contentView.chineseLabel.stringValue == "再见" &&
                     fixture.presenter.contentView.translationLabel.stringValue == "Goodbye",
                     "keyboard selection changes must refresh both Touch Bar lines")
        precondition(fixture.bridge.presentedBars.count == 1 && fixture.bridge.dismissedBars.isEmpty,
                     "selection and translation updates must reuse the already presented bar")
    }

    @MainActor private static func touchBarHidingOldOwnerPreservesCurrentOwner() {
        let fixture = TouchBarFixture()
        let oldOwner = UUID(), newOwner = UUID()
        fixture.presenter.show(owner: oldOwner, row: touchBarRow("你好", "Hello"), language: .english)
        fixture.environment.foregroundPID = 202
        fixture.presenter.show(owner: newOwner, row: touchBarRow("谢谢", "Thank you"), language: .english)
        fixture.presenter.hide(owner: oldOwner)
        precondition(fixture.bridge.dismissedBars.isEmpty &&
                     fixture.presenter.contentView.chineseLabel.stringValue == "谢谢",
                     "a delayed hide from the former input controller must not clear the current owner")
        fixture.presenter.hide(owner: newOwner)
        precondition(fixture.bridge.dismissedBars.count == 1 &&
                     fixture.bridge.dismissedBars[0] === fixture.bridge.presentedBars[0],
                     "the current owner must dismiss exactly the owned bar")
        fixture.presenter.hide(owner: newOwner)
        precondition(fixture.bridge.dismissedBars.count == 1,
                     "repeated dismissal must not dismiss unrelated or already hidden bars")
        requireTouchBarTextCleared(fixture)
    }

    @MainActor private static func touchBarUnavailableBridgeRemainsHarmless() {
        let fixture = TouchBarFixture()
        fixture.bridge.isAvailable = false
        let owner = UUID()
        fixture.presenter.show(owner: owner, row: touchBarRow("你好", "Hello"), language: .english)
        fixture.presenter.hide(owner: owner)
        precondition(fixture.bridge.presentedBars.count == 1 && fixture.bridge.dismissedBars.isEmpty,
                     "an unavailable presenter must not cause a dismiss call for a bar it never presented")
        requireTouchBarTextCleared(fixture)
        fixture.bridge.isAvailable = true
        fixture.presenter.show(owner: owner, row: touchBarRow("恢复", "Recovered"), language: .english)
        fixture.presenter.hide(owner: owner)
        precondition(fixture.bridge.presentedBars.count == 2 && fixture.bridge.dismissedBars.count == 1,
                     "a failed presentation must not leave state that prevents a later successful presentation")
    }

    @MainActor private static func touchBarRejectsInvalidEnvironmentBeforePresenting() {
        for secureInput in [true, false] {
            let fixture = TouchBarFixture()
            fixture.environment.secureInput = secureInput
            fixture.environment.foregroundPID = secureInput ? 101 : nil
            fixture.presenter.show(owner: UUID(), row: touchBarRow("你好", "Hello"), language: .english)
            precondition(fixture.bridge.presentedBars.isEmpty && fixture.bridge.dismissedBars.isEmpty,
                         "secure input or a missing foreground app must not present candidate text")
            requireTouchBarTextCleared(fixture)
        }
    }

    @MainActor private static func touchBarRejectsChangedForegroundDuringUpdate() {
        let fixture = TouchBarFixture()
        let owner = UUID()
        fixture.presenter.show(owner: owner, row: touchBarRow("你好", "Hello"), language: .english)
        fixture.environment.foregroundPID = 202
        fixture.presenter.show(owner: owner, row: touchBarRow("迟到", "Late translation"), language: .english)
        precondition(fixture.bridge.presentedBars.count == 1 && fixture.bridge.dismissedBars.count == 1,
                     "an update from the same owner after foreground changed must clear instead of republish")
        requireTouchBarTextCleared(fixture)
    }

    @MainActor private static func touchBarMonitorClearsSecureInput() async throws {
        let fixture = TouchBarFixture()
        let owner = UUID()
        fixture.presenter.show(owner: owner, row: touchBarRow("你好", "Hello"), language: .english)
        defer { fixture.presenter.hide(owner: owner) }
        fixture.environment.secureInput = true
        try await fixture.waitForDismissal()
        requireTouchBarTextCleared(fixture)
    }

    @MainActor private static func touchBarMonitorClearsChangedForeground() async throws {
        for foregroundPID: pid_t? in [202, nil] {
            let fixture = TouchBarFixture()
            let owner = UUID()
            fixture.presenter.show(owner: owner, row: touchBarRow("你好", "Hello"), language: .english)
            defer { fixture.presenter.hide(owner: owner) }
            fixture.environment.foregroundPID = foregroundPID
            try await fixture.waitForDismissal()
            requireTouchBarTextCleared(fixture)
        }
    }

    @MainActor private static func touchBarCancelledMonitorCannotDismissNewPresentation() async throws {
        let fixture = TouchBarFixture()
        let oldOwner = UUID(), newOwner = UUID()
        fixture.presenter.show(owner: oldOwner, row: touchBarRow("旧", "Old"), language: .english)
        fixture.presenter.hide(owner: oldOwner)
        fixture.environment.foregroundPID = 202
        fixture.presenter.show(owner: newOwner, row: touchBarRow("新", "New"), language: .english)
        defer { fixture.presenter.hide(owner: newOwner) }
        try await Task.sleep(for: .milliseconds(250))
        precondition(fixture.bridge.presentedBars.count == 2 && fixture.bridge.dismissedBars.count == 1 &&
                     fixture.presenter.contentView.chineseLabel.stringValue == "新",
                     "a cancelled monitor must not later clear the next owner's presentation")
    }

    @MainActor private static func touchBarLongContentIsBoundedAndAccessible() {
        let fixture = TouchBarFixture()
        let owner = UUID()
        defer { fixture.presenter.hide(owner: owner) }
        let chinese = String(repeating: "长候选内容", count: 40)
        let translation = String(repeating: "مرحبًا بك ", count: 80)
        fixture.presenter.show(owner: owner, row: touchBarRow(chinese, translation), language: .arabic)
        let view = fixture.presenter.contentView
        precondition(view.accessibilityLabel() == chinese + "，阿拉伯语译文：" + translation,
                     "accessibility must preserve complete long text and the translation language")
        precondition(view.chineseLabel.stringValue == chinese && view.translationLabel.stringValue == translation,
                     "visual truncation must not shorten the underlying bilingual strings")
        for label in [view.chineseLabel, view.translationLabel] {
            precondition(label.maximumNumberOfLines == 1 && label.lineBreakMode == .byTruncatingTail,
                         "Touch Bar lines must truncate within their compact one-line display")
            precondition(label.alignment == .center, "both lines must remain centered")
        }

        // Install in an offscreen window only to resolve real AppKit constraints.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 30),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 30))
        window.contentView = container
        defer { window.contentView = nil }
        container.addSubview(view)
        let availableWidth = view.widthAnchor.constraint(lessThanOrEqualToConstant: 700)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor), availableWidth
        ])
        container.layoutSubtreeIfNeeded()
        precondition(abs(view.bounds.width - 560) < 0.5 && view.bounds.height <= 30.5,
                     "long Touch Bar text must respect its maximum content width and compact height")
        // A Touch Bar offers an item a constrained slot. Resizing an NSWindow
        // instead would clamp its frame to AppKit's inferred minimum size.
        availableWidth.constant = 300
        container.layoutSubtreeIfNeeded()
        precondition(view.bounds.width > 0 && view.bounds.width <= 300.5,
                     "Touch Bar content must yield when the system offers a narrower slot")
        for label in [view.chineseLabel, view.translationLabel] {
            precondition(label.frame.minX >= 0 && label.frame.maxX <= view.bounds.width + 0.5,
                         "long labels must remain inside the supplied Touch Bar width")
            guard let cell = label.cell else { preconditionFailure("Touch Bar text label must have a cell") }
            precondition(cell.cellSize.height <= label.frame.height + 0.5,
                         "both Touch Bar lines must have sufficient native cell height to avoid clipped glyphs")
        }

        // Text below the width cap must fit without losing the cell's horizontal inset.
        availableWidth.constant = 700
        fixture.presenter.show(owner: owner,
                               row: touchBarRow("今天一起去散步", "Today, we are going for a walk in the park."),
                               language: .english)
        container.layoutSubtreeIfNeeded()
        precondition(view.bounds.width < 560,
                     "ordinary candidate text must use its natural width instead of the maximum")
        for label in [view.chineseLabel, view.translationLabel] {
            guard let cell = label.cell else { preconditionFailure("Touch Bar text label must have a cell") }
            precondition(cell.cellSize.width <= label.frame.width + 0.5,
                         "text below the Touch Bar width cap must fit without premature tail truncation")
            precondition(cell.cellSize.height <= label.frame.height + 0.5,
                         "natural-width Touch Bar lines must keep all glyphs vertically visible")
        }
        precondition(fixture.bridge.presentedBars.count == 1,
                     "content measurement updates must reuse the current Touch Bar presentation")
        precondition(!window.isVisible && !window.isKeyWindow,
                     "Touch Bar layout checks must not show a window or take input focus")
    }

    @MainActor private static func requireTouchBarTextCleared(_ fixture: TouchBarFixture) {
        precondition(fixture.presenter.contentView.chineseLabel.stringValue.isEmpty &&
                     fixture.presenter.contentView.translationLabel.stringValue.isEmpty &&
                     fixture.presenter.contentView.accessibilityLabel()?.isEmpty == true,
                     "dismissal must remove stale visual and accessible candidate text")
    }

    private static func touchBarRow(_ chinese: String, _ translation: String) -> CandidateRow {
        CandidateRow(candidate: Candidate(text: chinese, consumedCount: 2), translation: .ready(translation))
    }
}

@MainActor private final class TouchBarEnvironment {
    var foregroundPID: pid_t? = 101
    var secureInput = false
}

@MainActor private final class TouchBarBridge: CandidateTouchBarPresenting {
    var isAvailable = true
    private(set) var presentedBars: [NSTouchBar] = []
    private(set) var dismissedBars: [NSTouchBar] = []

    func present(_ bar: NSTouchBar) -> Bool {
        presentedBars.append(bar)
        return isAvailable
    }

    func dismiss(_ bar: NSTouchBar) { dismissedBars.append(bar) }
}

@MainActor private final class TouchBarFixture {
    let environment: TouchBarEnvironment
    let bridge: TouchBarBridge
    let presenter: CandidateTouchBar

    init() {
        let environment = TouchBarEnvironment()
        let bridge = TouchBarBridge()
        self.environment = environment
        self.bridge = bridge
        presenter = CandidateTouchBar(bridge: bridge, environment: {
            (environment.foregroundPID, environment.secureInput)
        })
    }

    func waitForDismissal() async throws {
        for _ in 0..<150 where bridge.dismissedBars.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(bridge.dismissedBars.count == 1,
                     "the foreground/secure-input monitor must dismiss the owned bar exactly once")
    }
}
