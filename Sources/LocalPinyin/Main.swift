import AppKit
import InputMethodKit
import PinyinInfrastructure

@main
struct LocalPinyinApp {
    @MainActor static var server: IMKServer?
    @MainActor static var instanceLock: SingleInstanceLock?

    @MainActor static func main() {
        let args = CommandLine.arguments
        let controllerName = NSStringFromClass(InputController.self)
        guard controllerName == "LocalPinyinInputController", NSClassFromString(controllerName) != nil else {
            print("Input controller runtime registration failed")
            exit(2)
        }
        if args.contains("--runtime-check") {
            print("controller=" + controllerName)
            print("bundle=" + (Bundle.main.bundleIdentifier ?? "missing"))
            return
        }
        if args.contains("--register") || args.contains("--source-status") {
            InputSourceRegistration.run(enable: args.contains("--register"))
            return
        }
        let isDemo = args.contains("--demo") || args.contains("--snapshot")
        if !isDemo {
            do {
                let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("local.pinyinlab.inputmethod", isDirectory: true)
                instanceLock = try SingleInstanceLock.acquire(in: directory)
                guard instanceLock != nil else {
                    NSLog("LocalPinyin lifecycle: another input service is already running")
                    return
                }
            } catch {
                NSLog("LocalPinyin lifecycle: cannot acquire input service lock")
                exit(1)
            }
            NSLog("LocalPinyin lifecycle: creating IMKServer")
            server = IMKServer(name: "local.pinyinlab.inputmethod_Connection", bundleIdentifier: "local.pinyinlab.inputmethod")
            guard server != nil else {
                NSLog("LocalPinyin lifecycle: IMKServer creation failed")
                exit(1)
            }
            NSLog("LocalPinyin lifecycle: IMKServer created; bundle=%@", Bundle.main.bundlePath)
        }
        if !isDemo { PinyinSession.shared.warm() }
        let app = NSApplication.shared
        if isDemo {
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                do { try await DemoRunner.run(arguments: args) }
                catch { print("Synthetic-input demo failed: \(error)"); exit(1) }
            }
        }
        app.run()
    }
}
