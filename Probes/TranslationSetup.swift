import SwiftUI
import Translation

@main
struct TranslationSetup: App {
    var body: some Scene {
        WindowGroup("本地翻译验证") { SetupView().frame(width: 480, height: 240) }
    }
}

struct SetupView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("苹果本地翻译验证").font(.title2)
            Text("仅使用合成文本：你好、谢谢、学习。")
            Text("请在苹果系统提示中准备中英文离线语言包。完成后自动测试三条合成文本，结果写入验证日志。")
        }
        .padding(24)
        .translationTask(source: Locale.Language(identifier: "zh-Hans"), target: Locale.Language(identifier: "en")) { session in
            do {
                try await session.prepareTranslation()
                var output: [String] = []
                for text in ["你好", "谢谢", "学习"] {
                    output.append("\(text) → \(try await session.translate(text).targetText)")
                }
                print("TRANSLATION_SUCCESS\n" + output.joined(separator: "\n"))
            } catch {
                print("TRANSLATION_ERROR: \(error)")
            }
            fflush(stdout)
        }
    }
}
