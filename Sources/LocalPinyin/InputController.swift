import AppKit
import InputMethodKit
import Carbon
import PinyinApplication
import PinyinInfrastructure
import PinyinPresentation

/// IMK lifecycle and event adaptation only. Composition rules live in InputSession.
@objc(LocalPinyinInputController)
@MainActor final class InputController: IMKInputController {
    private var host: IMKHost?
    private lazy var session = InputSession(
        provider: PinyinSession.shared,
        translator: AppleTranslator(),
        speaker: EnglishSpeaker(),
        presenter: CandidatePanel(anchor: { [weak self] in self?.host?.anchor ?? .zero }))

    override func activateServer(_ sender: Any!) {
        NSLog("LocalPinyin lifecycle: input controller activated")
        super.activateServer(sender)
        nonisolated(unsafe) let controller = self
        MainActor.assumeIsolated { controller.session.activate() }
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        // IMK's Objective-C callbacks run on the service main thread, but the SDK
        // does not annotate them with Swift actor isolation. Assert at this boundary.
        nonisolated(unsafe) let controller = self
        nonisolated(unsafe) let callbackEvent = event
        nonisolated(unsafe) let callbackSender = sender
        return MainActor.assumeIsolated {
            guard let event = callbackEvent, event.type == .keyDown, let client = callbackSender as? any IMKTextInput else { return false }
            guard !IsSecureEventInputEnabled() else { controller.session.cancel(); return false }
            if controller.host?.client !== client { controller.host = IMKHost(client: client) }
            guard let host = controller.host else { return false }
            return controller.session.handle(KeyStroke(event: event), host: host)
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
            controller.session.deactivate()
            controller.host = nil
        }
    }
}
