import AppKit
import Carbon
import ObjectiveC
import PinyinCore

@MainActor
public protocol CandidateTouchBarDisplaying: AnyObject {
    func show(owner: UUID, row: CandidateRow, language: TranslationLanguage)
    func hide(owner: UUID)
}

/// One bar belongs to the currently displayed candidate panel, even when IMK
/// keeps multiple input controllers alive for different applications.
@MainActor
public final class CandidateTouchBar: CandidateTouchBarDisplaying {
    public static let shared = CandidateTouchBar()

    private let bridge: any CandidateTouchBarPresenting
    private let environment: () -> (foregroundPID: pid_t?, secureInput: Bool)
    private let bar = NSTouchBar()
    package let contentView = CandidateTouchBarView()
    private var owner: UUID?
    private var foregroundPID: pid_t?
    private var presented = false
    private var monitorTask: Task<Void, Never>?

    private convenience init() {
        self.init(bridge: SystemModalCandidateTouchBar(), environment: {
            (NSWorkspace.shared.frontmostApplication?.processIdentifier, IsSecureEventInputEnabled())
        })
    }

    package init(bridge: any CandidateTouchBarPresenting,
                 environment: @escaping () -> (foregroundPID: pid_t?, secureInput: Bool)) {
        self.bridge = bridge
        self.environment = environment
        let identifier = NSTouchBarItem.Identifier("local.pinyinlab.selected-candidate")
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = contentView
        item.visibilityPriority = .high
        bar.templateItems = [item]
        bar.defaultItemIdentifiers = [identifier]
        bar.principalItemIdentifier = identifier
    }

    deinit { monitorTask?.cancel() }

    public func show(owner: UUID, row: CandidateRow, language: TranslationLanguage) {
        let state = environment()
        guard !state.secureInput, let pid = state.foregroundPID else {
            dismiss()
            return
        }
        // Ignore a late update from the old host while focus is changing.
        if self.owner == owner, foregroundPID != pid {
            dismiss()
            return
        }
        self.owner = owner
        foregroundPID = pid
        contentView.update(chinese: row.text, translation: row.translationText(for: language), language: language)
        if !presented { presented = bridge.present(bar) }
        guard presented else { return }
        if monitorTask == nil {
            monitorTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(100)) }
                    catch { return }
                    guard let self, self.presented else { return }
                    let state = self.environment()
                    guard !state.secureInput, state.foregroundPID == self.foregroundPID else {
                        self.dismiss()
                        return
                    }
                }
            }
        }
    }

    public func hide(owner: UUID) {
        guard self.owner == owner else { return }
        dismiss()
    }

    private func dismiss() {
        monitorTask?.cancel()
        monitorTask = nil
        if presented { bridge.dismiss(bar) }
        presented = false
        owner = nil
        foregroundPID = nil
        contentView.update(chinese: "", translation: "", language: .english)
    }
}

@MainActor
package protocol CandidateTouchBarPresenting: AnyObject {
    func present(_ bar: NSTouchBar) -> Bool
    func dismiss(_ bar: NSTouchBar)
}

/// AppKit's public responder-chain API only serves the foreground application.
/// This background IME therefore uses an optional runtime bridge. Keep private
/// selectors isolated here; unavailable systems retain normal candidate input.
@MainActor
private final class SystemModalCandidateTouchBar: CandidateTouchBarPresenting {
    private let presentSelector = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
    private let dismissSelector = NSSelectorFromString("dismissSystemModalTouchBar:")

    func present(_ bar: NSTouchBar) -> Bool {
        guard let method = class_getClassMethod(NSTouchBar.self, presentSelector),
              class_getClassMethod(NSTouchBar.self, dismissSelector) != nil else { return false }
        typealias Present = @convention(c) (AnyClass, Selector, NSTouchBar, NSString?) -> Void
        let invoke = unsafeBitCast(method_getImplementation(method), to: Present.self)
        invoke(NSTouchBar.self, presentSelector, bar, nil)
        return true
    }

    func dismiss(_ bar: NSTouchBar) {
        guard let method = class_getClassMethod(NSTouchBar.self, dismissSelector) else { return }
        typealias Dismiss = @convention(c) (AnyClass, Selector, NSTouchBar) -> Void
        let invoke = unsafeBitCast(method_getImplementation(method), to: Dismiss.self)
        invoke(NSTouchBar.self, dismissSelector, bar)
    }
}

@MainActor
package final class CandidateTouchBarView: NSView {
    package let chineseLabel = NSTextField(labelWithString: "")
    package let translationLabel = NSTextField(labelWithString: "")
    private var preferredWidth: NSLayoutConstraint!

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 30))
        translatesAutoresizingMaskIntoConstraints = false
        for label in [chineseLabel, translationLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            addSubview(label)
        }
        chineseLabel.font = .systemFont(ofSize: 13, weight: .medium)
        chineseLabel.textColor = .white
        translationLabel.font = .systemFont(ofSize: 11)
        translationLabel.textColor = NSColor(white: 0.8, alpha: 1)
        preferredWidth = widthAnchor.constraint(equalToConstant: 160)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            widthAnchor.constraint(lessThanOrEqualToConstant: 560), preferredWidth,
            chineseLabel.topAnchor.constraint(equalTo: topAnchor),
            chineseLabel.heightAnchor.constraint(equalToConstant: 16),
            chineseLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            chineseLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            translationLabel.topAnchor.constraint(equalTo: chineseLabel.bottomAnchor),
            translationLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            translationLabel.leadingAnchor.constraint(equalTo: chineseLabel.leadingAnchor),
            translationLabel.trailingAnchor.constraint(equalTo: chineseLabel.trailingAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(chinese: String, translation: String, language: TranslationLanguage) {
        chineseLabel.stringValue = chinese
        translationLabel.stringValue = translation
        let chineseWidth = chineseLabel.cell?.cellSize.width ?? 0
        let translationWidth = translationLabel.cell?.cellSize.width ?? 0
        preferredWidth.constant = min(560, max(120, ceil(max(chineseWidth, translationWidth)) + 16))
        setAccessibilityLabel(chinese + (translation.isEmpty ? "" : "，\(language.displayName)译文：" + translation))
        NSAccessibility.post(element: self, notification: .valueChanged)
    }
}
