import AppKit
import InputMethodKit
import Carbon
import PinyinApplication
import PinyinInfrastructure
import PinyinPresentation

/// IMK lifecycle and event adaptation only. Composition rules live in InputSession.
@objc(LocalPinyinInputController)
@MainActor final class InputController: IMKInputController {
    private static let modeState = InputModeState()
    private let capsLockController = CapsLockController()
    private var isActive = false
    private var lifecycleRevision: UInt64 = 0
    private var capsSyncGeneration: UInt64 = 0
    private var capsSyncTask: Task<Void, Never>?
    private var pendingCapsState: Bool?
    private var capsAcknowledgement: (enabled: Bool, timestamp: TimeInterval)?
    private var speechActivityBaseline: [UInt32]?
    private var speechGestureBeganAt: TimeInterval?
    private var host: IMKHost?
    private lazy var session = InputSession(
        provider: PinyinSession.shared,
        translator: AppleTranslator(),
        speaker: LocalSpeechPlayer(),
        presenter: CandidatePanel(anchor: { [weak self] in self?.host?.anchor ?? .zero },
                                  windowLevel: { [weak self] in self?.host?.windowLevel ?? 0 }),
        modeState: InputController.modeState,
        translationLanguage: TranslationPreferences.targetLanguage,
        speechShortcut: SpeechShortcutPreferences.shortcut)

    @objc private func translationLanguageDidChange(_ notification: Notification) {
        guard isActive else { return }
        session.setTranslationLanguage(TranslationPreferences.targetLanguage)
    }

    @objc private func speechShortcutDidChange(_ notification: Notification) {
        guard isActive else { return }
        session.setSpeechShortcut(SpeechShortcutPreferences.shortcut)
        speechActivityBaseline = nil
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(InputEvent.recognizedEvents.rawValue)
    }

    override func menu() -> NSMenu! {
        nonisolated(unsafe) let controller = self
        // IMK requests menus synchronously on its main thread. Borrow the result
        // across the same checked boundary without making NSMenu Sendable.
        nonisolated(unsafe) var result: NSMenu?
        MainActor.assumeIsolated {
            let menu = NSMenu(title: "拼音")
            let item = NSMenuItem(title: "拼音设置…", action: #selector(openSettings(_:)), keyEquivalent: "")
            item.target = controller
            menu.addItem(item)
            result = menu
        }
        return result
    }

    @objc private func openSettings(_ sender: Any?) {
        let applications = [URL(fileURLWithPath: "/Applications", isDirectory: true),
                            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
        var locations = applications.flatMap { directory in
            ["拼音设置.app", "PinyinSettings.app"].map { directory.appendingPathComponent($0) }
        }
        if let resources = Bundle.main.resourceURL {
            locations.append(resources.appendingPathComponent("PinyinSettings.app"))
        }
        let settings = locations.first { Bundle(url: $0)?.bundleIdentifier == "local.pinyinlab.settings" }
        if settings.map({ NSWorkspace.shared.open($0) }) != true {
            let alert = NSAlert()
            alert.messageText = "无法打开拼音设置"
            alert.informativeText = "请重新安装完整的拼音输入法和“拼音设置”应用，然后重试。"
            alert.runModal()
        }
    }

    override func activateServer(_ sender: Any!) {
        NSLog("LocalPinyin lifecycle: input controller activated")
        super.activateServer(sender)
        nonisolated(unsafe) let controller = self
        MainActor.assumeIsolated {
            controller.lifecycleRevision &+= 1
            controller.isActive = true
            let notifications = DistributedNotificationCenter.default()
            notifications.removeObserver(controller, name: TranslationPreferences.didChangeNotification,
                                         object: TranslationPreferences.notificationObject)
            notifications.addObserver(controller, selector: #selector(translationLanguageDidChange(_:)),
                                      name: TranslationPreferences.didChangeNotification,
                                      object: TranslationPreferences.notificationObject, suspensionBehavior: .deliverImmediately)
            notifications.removeObserver(controller, name: SpeechShortcutPreferences.didChangeNotification,
                                         object: SpeechShortcutPreferences.notificationObject)
            notifications.addObserver(controller, selector: #selector(speechShortcutDidChange(_:)),
                                      name: SpeechShortcutPreferences.didChangeNotification,
                                      object: SpeechShortcutPreferences.notificationObject, suspensionBehavior: .deliverImmediately)
            controller.session.setTranslationLanguage(TranslationPreferences.targetLanguage)
            controller.session.setSpeechShortcut(SpeechShortcutPreferences.shortcut)
            controller.speechActivityBaseline = nil
            controller.session.cancelSpeechShortcutGesture()
            controller.cancelCapsSync()
            controller.session.activate(capsLock: controller.capsLockController.isEnabled()
                ?? NSEvent.modifierFlags.contains(.capsLock))
        }
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        // IMK's Objective-C callbacks run on the service main thread, but the SDK
        // does not annotate them with Swift actor isolation. Assert at this boundary.
        nonisolated(unsafe) let controller = self
        nonisolated(unsafe) let callbackEvent = event
        nonisolated(unsafe) let callbackSender = sender
        return MainActor.assumeIsolated {
            guard let event = callbackEvent, let client = callbackSender as? any IMKTextInput else { return false }
            guard !IsSecureEventInputEnabled() else {
                controller.speechActivityBaseline = nil
                controller.cancelCapsSync()
                controller.session.cancel()
                controller.session.synchronizeCapsLock(event.modifierFlags.contains(.capsLock))
                return false
            }
            // A queued keyDown can still carry the flags from before our HID
            // request. Real Caps key events always keep their own state.
            let capsOverride = controller.host?.client === client ? controller.pendingCapsState ?? controller.capsAcknowledgement.flatMap {
                event.timestamp <= $0.timestamp ? $0.enabled : nil
            } : nil
            let input = InputEvent(event: event, capsLockOverride: capsOverride)
            // Adding flagsChanged disables IMK's default outside-click commit.
            // Raw mouse events do not provide a reliable remote document index:
            // finish composition and let the client process the click normally.
            if case .mouseDown = input {
                controller.session.finishComposition()
                return false
            }
            if case .unhandled = input {
                controller.session.cancelSpeechShortcutGesture()
                if controller.host?.client === client, let host = controller.host,
                   event.modifierFlags.intersection([.command, .option, .control, .shift, .function]).isEmpty {
                    _ = controller.session.handleSpeechModifiers([], host: host)
                }
                return false
            }
            if controller.host?.client !== client {
                controller.lifecycleRevision &+= 1
                controller.cancelCapsSync()
                controller.speechActivityBaseline = nil
                controller.session.cancelSpeechShortcutGesture()
                controller.host = IMKHost(client: client)
            }
            guard let host = controller.host else { return false }
            let revision = controller.lifecycleRevision
            switch input {
            case .key(let key):
                let previousMode = controller.session.mode
                let previousUppercase = controller.session.isUppercaseLocked
                let handled = controller.session.handle(key, host: host)
                if previousMode != controller.session.mode || previousUppercase != controller.session.isUppercaseLocked {
                    controller.synchronizeCapsIndicator(host: host, revision: revision)
                }
                return handled
            case .capsLock(let enabled, let modifiers):
                controller.session.cancelSpeechShortcutGesture()
                if (controller.pendingCapsState ?? controller.capsAcknowledgement?.enabled) != enabled {
                    controller.cancelCapsSync()
                    controller.capsAcknowledgement = nil
                }
                if controller.session.handleCapsLock(enabled, modifiers: modifiers, host: host) {
                    controller.synchronizeCapsIndicator(host: host, revision: revision)
                }
                return modifiers.isEmpty || modifiers == [.shift]
            case .modifiersChanged(let modifiers):
                controller.checkSpeechShortcutActivity(modifiers: modifiers, timestamp: event.timestamp)
                // Flags still belong to the foreground app. The gesture only
                // observes them; it must never swallow Command/Option state.
                _ = controller.session.handleSpeechModifiers(modifiers, host: host)
                return false
            case .shortcutCancelled:
                controller.session.cancelSpeechShortcutGesture()
                // A plain character's keyUp is also a clean baseline. Blocking
                // here until another flagsChanged would discard the first
                // speech gesture immediately after finishing a pinyin word.
                if event.modifierFlags.intersection([.command, .option, .control, .shift, .function]).isEmpty {
                    _ = controller.session.handleSpeechModifiers([], host: host)
                }
                return false
            case .mouseDown, .unhandled: return false
            }
        }
    }

    /// IMK may not receive a key consumed by a system/menu shortcut. Compare
    /// session event counters as well, without installing a global event tap.
    private func checkSpeechShortcutActivity(modifiers: KeyModifiers, timestamp: TimeInterval) {
        let eventTypes: [CGEventType] = [
            .keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
        ]
        let counters = eventTypes.map { CGEventSource.counterForEventType(.combinedSessionState, eventType: $0) }
        if speechActivityBaseline == nil { speechGestureBeganAt = timestamp }
        // Compare event time too: a queued initial flagsChanged can arrive after
        // a system shortcut's keyDown/keyUp already advanced the counters.
        let beganAt = speechGestureBeganAt ?? timestamp
        let interveningEvent = eventTypes.contains {
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
            return elapsed.isFinite && now - elapsed > beganAt + 0.001
        }
        let modifierCodes: Set<CGKeyCode> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        let otherKeyHeld = (CGKeyCode(0)...CGKeyCode(127)).contains {
            !modifierCodes.contains($0) && CGEventSource.keyState(.combinedSessionState, key: $0)
        }
        let mouseHeld = [CGMouseButton.left, .right, .center].contains {
            CGEventSource.buttonState(.combinedSessionState, button: $0)
        }
        if otherKeyHeld || mouseHeld || interveningEvent || (speechActivityBaseline.map { $0 != counters } ?? false) {
            session.cancelSpeechShortcutGesture()
        }
        if modifiers.isEmpty { speechActivityBaseline = nil; speechGestureBeganAt = nil }
        else if speechActivityBaseline == nil { speechActivityBaseline = counters }
    }

    /// Hardware writes happen only for the still-active host. In particular,
    /// a synchronous commit that switches apps must not change another source's LED.
    private func ownsCapsSync(host expectedHost: IMKHost, revision: UInt64) -> Bool {
        guard isActive, host === expectedHost, lifecycleRevision == revision, !IsSecureEventInputEnabled() else { return false }
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
        let identifier = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        return identifier == "local.pinyinlab.inputmethod.Hans" || identifier == "local.pinyinlab.inputmethod"
    }

    private func cancelCapsSync() {
        capsSyncGeneration &+= 1
        capsSyncTask?.cancel()
        capsSyncTask = nil
        pendingCapsState = nil
        capsAcknowledgement = nil
    }

    private func synchronizeCapsIndicator(host expectedHost: IMKHost, revision: UInt64) {
        guard ownsCapsSync(host: expectedHost, revision: revision) else { return }
        cancelCapsSync()
        let desired = session.mode == .englishDirect
        let expectedUppercase = session.isUppercaseLocked
        let generation = capsSyncGeneration
        // IOHID publishes a modifier event asynchronously; record our expected
        // state first so that its echo cannot toggle the mode or uppercase again.
        session.acknowledgeCapsLock(desired)
        guard capsLockController.isEnabled() != desired else {
            capsAcknowledgement = (desired, ProcessInfo.processInfo.systemUptime)
            return
        }
        pendingCapsState = desired
        guard capsLockController.requestEnabled(desired) else {
            pendingCapsState = nil
            restoreActualCapsState()
            return
        }
        capsSyncTask = Task { [weak self, weak expectedHost] in
            for _ in 0..<15 {
                do { try await Task.sleep(for: .milliseconds(20)) }
                catch { return }
                guard let self, let expectedHost, self.capsSyncGeneration == generation,
                      self.ownsCapsSync(host: expectedHost, revision: revision),
                      (self.session.mode == .englishDirect) == desired,
                      self.session.isUppercaseLocked == expectedUppercase else { return }
                if self.capsLockController.isEnabled() == desired {
                    self.pendingCapsState = nil
                    self.capsAcknowledgement = (desired, ProcessInfo.processInfo.systemUptime)
                    self.capsSyncTask = nil
                    return
                }
            }
            guard let self, self.capsSyncGeneration == generation else { return }
            self.capsSyncTask = nil
            self.pendingCapsState = nil
            self.restoreActualCapsState()
        }
    }

    private func restoreActualCapsState() {
        capsAcknowledgement = nil
        NSLog("LocalPinyin Caps Lock: system lock synchronization was not confirmed")
        if let actual = capsLockController.isEnabled() {
            let changesMode = (session.mode == .englishDirect) != actual
            session.synchronizeCapsLock(actual)
            if changesMode { session.finishComposition() }
        }
    }

    override func mouseDown(onCharacterIndex index: Int, coordinate point: NSPoint,
                            withModifier flags: Int, continueTracking keepTracking: UnsafeMutablePointer<ObjCBool>!,
                            client sender: Any!) -> Bool {
        keepTracking?.pointee = false
        nonisolated(unsafe) let controller = self
        nonisolated(unsafe) let callbackSender = sender
        return MainActor.assumeIsolated {
            controller.session.cancelSpeechShortcutGesture()
            guard !IsSecureEventInputEnabled() else { controller.session.cancel(); return false }
            guard let client = callbackSender as? any IMKTextInput else { return false }
            // Never submit an old composition into a new client's document.
            let marked = client.markedRange()
            if controller.host?.client !== client || marked.location == NSNotFound || !NSLocationInRange(index, marked) {
                controller.session.finishComposition()
            }
            return false
        }
    }

    override func commitComposition(_ sender: Any!) {
        nonisolated(unsafe) let controller = self
        MainActor.assumeIsolated {
            controller.speechActivityBaseline = nil
            controller.session.deactivate()
        }
    }

    override func deactivateServer(_ sender: Any!) {
        NSLog("LocalPinyin lifecycle: input controller deactivated")
        nonisolated(unsafe) let controller = self
        MainActor.assumeIsolated {
            controller.lifecycleRevision &+= 1
            controller.isActive = false
            DistributedNotificationCenter.default().removeObserver(controller,
                name: TranslationPreferences.didChangeNotification, object: TranslationPreferences.notificationObject)
            DistributedNotificationCenter.default().removeObserver(controller,
                name: SpeechShortcutPreferences.didChangeNotification, object: SpeechShortcutPreferences.notificationObject)
            controller.speechActivityBaseline = nil
            controller.cancelCapsSync()
            controller.host = nil
            controller.session.deactivate()
        }
    }
}
