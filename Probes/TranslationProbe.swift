import Foundation
import Translation

@main
struct TranslationProbe {
    @MainActor static func main() async {
        alarm(20)
        let translator = AppleTranslator()
        let status = await translator.status()
        print("zh-Hans -> en: \(status)")
        guard status == .installed else {
            print("SKIP: Models not installed; no download requested.")
            return
        }
        do {
            let samples = ["你好", "谢谢", "学习", "现在北京时间几点钟"]
            let translated = try await translator.translate(samples)
            for (source, target) in zip(samples, translated) { print("\(source) -> \(target)") }
            let repeated = try await translator.translate(["学习", "你好", "学习"])
            guard repeated == [translated[2], translated[0], translated[2]] else {
                print("FAIL: cached duplicate/order mapping"); exit(2)
            }
            print("PASS: cached duplicate/order mapping")
        } catch {
            print("Translation failed: \(error)")
            exit(1)
        }
    }
}
