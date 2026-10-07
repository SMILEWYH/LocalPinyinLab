import AppKit
import PinyinPresentation

extension PresentationChecks {
    /// Exercise the real panel's configuration without ordering a window onscreen.
    @MainActor static func checkCandidateWindowBehavior() {
        var hostLevel = NSWindow.Level.normal.rawValue
        let presenter = CandidatePanel(windowLevel: { hostLevel })
        let window = presenter.panel
        let baseline = NSWindow.Level.popUpMenu.rawValue

        presenter.updateWindowLevel()
        precondition(window.level.rawValue == baseline,
                     "ordinary editors must preserve the candidate window's popup level")

        hostLevel = baseline
        presenter.updateWindowLevel()
        precondition(window.level.rawValue > hostLevel,
                     "a host at the popup level must not cover candidates at the same level")

        hostLevel = NSWindow.Level.screenSaver.rawValue
        presenter.updateWindowLevel()
        precondition(window.level.rawValue > hostLevel,
                     "the candidate window must follow a host above the original popup level")

        hostLevel = NSWindow.Level.normal.rawValue
        presenter.updateWindowLevel()
        precondition(window.level.rawValue == baseline,
                     "returning to an ordinary editor must discard the previous elevated level")

        precondition(window.collectionBehavior.contains(.canJoinAllSpaces),
                     "candidates must be eligible for the current Space")
        precondition(window.collectionBehavior.contains(.canJoinAllApplications),
                     "candidates must be eligible for other apps' Stage Manager and full screen spaces")
        precondition(window.collectionBehavior.contains(.fullScreenAuxiliary),
                     "candidates must retain auxiliary full screen behavior")
        precondition(window.styleMask.contains(.nonactivatingPanel),
                     "candidate presentation must not activate the input method over the editor")
        precondition(!window.hidesOnDeactivate && window.ignoresMouseEvents,
                     "the editor must retain focus and mouse input while candidates are visible")
        precondition(!window.isVisible && !window.isKeyWindow && !window.isMainWindow,
                     "level updates alone must never show or focus a candidate window")
    }
}
