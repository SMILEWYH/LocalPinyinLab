import Carbon
import Foundation
func string(_ source: TISInputSource, _ key: CFString) -> String {
    guard let value = TISGetInputSourceProperty(source, key) else { return "" }
    return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
}
let args = CommandLine.arguments
if args.count == 3 && args[1] == "register" {
    print("register_status=\(TISRegisterInputSource(URL(fileURLWithPath: args[2]) as CFURL))")
}
let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
print("current_id=" + string(current, kTISPropertyInputSourceID))
print("current_name=" + string(current, kTISPropertyLocalizedName))
let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
if args.count == 2 && ["select-test", "restore-original"].contains(args[1]) {
    let desired = args[1] == "select-test" ? "local.pinyinlab.inputmethod.Hans" : "com.apple.inputmethod.SCIM.ITABC"
    for source in sources where string(source, kTISPropertyInputSourceID) == desired {
        print("select_id=\(desired) status=\(TISSelectInputSource(source))")
    }
    RunLoop.current.run(until: Date().addingTimeInterval(1))
}

for source in sources where string(source, kTISPropertyInputSourceID).hasPrefix("local.pinyinlab") {
    if args.count == 2 && args[1] == "enable" {
        print("enable_status=\(TISEnableInputSource(source))")
    }
    if let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) {
        let value = Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
        print("enabled=\(CFBooleanGetValue(value))")
    }
    print("registered_id=" + string(source, kTISPropertyInputSourceID))
    print("registered_name=" + string(source, kTISPropertyLocalizedName))
}

if args.count == 2 && args[1] == "enable" { RunLoop.current.run(until: Date().addingTimeInterval(3)) }
