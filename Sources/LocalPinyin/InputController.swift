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
    private var host: IMKHost?
    private lazy var session = InputSession(
        provider: PinyinSession.shared,
        translator: AppleTranslator(),
        speaker: EnglishSpeaker(),
        presenter: CandidatePanel(anchor: { [weak self] in self?.host?.anchor ?? .zero }),
        modeState: InputController.modeState)

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(InputEvent.recognizedEvents.rawValue)
    }

    override func activateServer(_ sender: Any!) {
        NSLog("LocalPinyin lifecycle: input controller activated")
        super.activateServer(sender)
        nonisolated(unsafe) let controller = self
        MainActor.assumeIsolated {
            controller.session.activate(capsLock: NSEvent.modifierFlags.contains(.capsLock))
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
                controller.session.cancel()
                controller.session.synchronizeCapsLock(event.modifierFlags.contains(.capsLock))
                return false
            }
            let input = InputEvent(event: event)
            // Adding flagsChanged disables IMK's default outside-click commit.
            // Raw mouse events do not provide a reliable remote document index:
            // finish composition and let the client process the click normally.
            if case .mouseDown = input {
                controller.session.finishComposition()
                return false
            }
            if case .unhandled = input { return false }
            if controller.host?.client !== client { controller.host = IMKHost(client: client) }
            guard let host = controller.host else { return false }
            switch input {
            case .key(let key): return controller.session.handle(key, host: host)
            case .capsLock(let enabled, let modifiers):
                _ = controller.session.handleCapsLock(enabled, modifiers: modifiers, host: host)
                return modifiers.isEmpty || modifiers == [.shift]
            case .mouseDown, .unhandled: return false
            }
        }
    }

    override func mouseDown(onCharacterIndex index: Int, coordinate point: NSPoint,
                            withModifier flags: Int, continueTracking keepTracking: UnsafeMutablePointer<ObjCBool>!,
                            client sender: Any!) -> Bool {
        keepTracking?.pointee = false
        nonisolated(unsafe) let controller = self
        nonisolated(unsafe) let callbackSender = sender
        return MainActor.assumeIsolated {
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
        MainActor.assumeIsolated { controller.session.deactivate() }
    }

    override func deactivateServer(_ sender: Any!) {
        NSLog("LocalPinyin lifecycle: input controller deactivated")
        nonisolated(unsafe) let controller = self
        MainActor.assumeIsolated {
            controller.host = nil
            controller.session.deactivate()
        }
    }
}
