import Carbon
import Foundation

@MainActor
public enum InputSourceRegistration {
    static let rootID = "local.pinyinlab.inputmethod"
    static func name(_ source: TISInputSource, key: CFString) -> String {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return "" }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
    static func flag(_ source: TISInputSource, key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }
    public static func run(enable: Bool) {
        if enable { print("register=\(TISRegisterInputSource(Bundle.main.bundleURL as CFURL))") }
        let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
        for id in [rootID, rootID + ".Hans"] {
            for source in sources where name(source, key: kTISPropertyInputSourceID) == id {
                print("id=\(id) type=\(name(source, key: kTISPropertyInputSourceType)) name=\(name(source, key: kTISPropertyLocalizedName))")
                print("enableCapable=\(flag(source, key: kTISPropertyInputSourceIsEnableCapable)) selectCapable=\(flag(source, key: kTISPropertyInputSourceIsSelectCapable)) enabled=\(flag(source, key: kTISPropertyInputSourceIsEnabled))")
                if enable { print("enable=\(TISEnableInputSource(source))") }
            }
        }
        let active = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        print("current=\(name(active, key: kTISPropertyInputSourceID))")
        if enable { RunLoop.current.run(until: Date().addingTimeInterval(3)) }
    }
}
