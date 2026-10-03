import AppKit
import InputMethodKit

@main
struct LocalPinyinApp {
    @MainActor static var server: IMKServer?
    @MainActor static var panel: CandidatePanel?

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
                do {
                    let sample = args.contains("--long-sample") ? "xianzaibeijingshijianjidianzhong" : (args.contains("--candidate-sample") ? "pingying" : "xiexie")
                    let engine = ApplePinyinEngine(workerRoot: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Worker"))
                    var rows = try await Task.detached { try engine.candidates(for: sample) }.value
                    let translator = AppleTranslator()
                    if await translator.status() == .installed {
                        let indices = rows.indices.prefix(9).filter { rows[$0].needsTranslation }
                        let translations = try await translator.translate(indices.map { rows[$0].text })
                        for (index, translation) in zip(indices, translations) {
                            rows[index].translation = translation
                            rows[index].translationReady = true
                        }
                    } else {
                        rows = rows.map { Candidate(text: $0.text, translation: "未安装中英离线语言包") }
                    }
                    if let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) {
                        let view = CandidateView(rows: rows, pinyin: sample, highlighted: 0, footer: "1/\(max(1, (rows.count + 8) / 9))")
                        try view.writePNG(to: URL(fileURLWithPath: args[index + 1]))
                        print("Real Apple candidates: " + rows.map(\.text).joined(separator: ", "))
                        exit(0)
                    }
                    panel = CandidatePanel()
                    panel?.show(rows: rows, pinyin: sample, selected: 0, page: 0, totalPages: max(1, (rows.count + 8) / 9),
                                anchor: NSRect(x: NSScreen.main?.visibleFrame.midX ?? 500, y: NSScreen.main?.visibleFrame.midY ?? 500, width: 0, height: 16))
                } catch {
                    print("Synthetic-input demo failed: \(error)")
                    exit(1)
                }
            }
        }
        app.run()
    }
}
