import Carbon
import Foundation

func string(_ source: TISInputSource, _ key: CFString) -> String {
    guard let value = TISGetInputSourceProperty(source, key) else { return "" }
    return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
}

func flag(_ source: TISInputSource, _ key: CFString) -> Bool? {
    guard let value = TISGetInputSourceProperty(source, key) else { return nil }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
}

func describe(_ source: TISInputSource, prefix: String) {
    print(prefix + "_id=" + string(source, kTISPropertyInputSourceID))
    print(prefix + "_name=" + string(source, kTISPropertyLocalizedName))
    print(prefix + "_ascii=" + (flag(source, kTISPropertyInputSourceIsASCIICapable).map(String.init) ?? "unknown"))
}

let args = CommandLine.arguments
if args.count == 3 && args[1] == "register" {
    print("register_status=\(TISRegisterInputSource(URL(fileURLWithPath: args[2]) as CFURL))")
}
let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
describe(current, prefix: "current")
let currentASCII = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue()
if let ascii = currentASCII {
    print("current_ascii_id=" + string(ascii, kTISPropertyInputSourceID))
    print("current_ascii_name=" + string(ascii, kTISPropertyLocalizedName))
}
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
    describe(source, prefix: "registered")
}

if args.count == 2 && args[1] == "enable" { RunLoop.current.run(until: Date().addingTimeInterval(3)) }

// Read-only installation check. A valid plist is not proof that macOS refreshed
// its registration cache; check the metadata TIS actually uses for switching.
if args.count == 2 && args[1] == "--check-registration" {
    let requiredIDs = ["local.pinyinlab.inputmethod", "local.pinyinlab.inputmethod.Hans"]
    var failures: [String] = []
    for id in requiredIDs {
        let matches = sources.filter { string($0, kTISPropertyInputSourceID) == id }
        if matches.isEmpty {
            failures.append("missing input source: \(id)")
        }
        for source in matches where flag(source, kTISPropertyInputSourceIsASCIICapable) != false {
            failures.append("\(id) must be registered as non-ASCII; registration may be stale")
        }
    }
    if let ascii = currentASCII, requiredIDs.contains(string(ascii, kTISPropertyInputSourceID)) {
        failures.append("Chinese-English Pinyin is still the current ASCII input source")
    }
    for failure in failures { print("registration_error=" + failure) }
    print("registration_check=" + (failures.isEmpty ? "passed" : "failed"))
    if !failures.isEmpty { exit(1) }
}
