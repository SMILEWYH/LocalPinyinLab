import SwiftUI
import Translation

@main
struct TranslationSetup: App {
    var body: some Scene {
        WindowGroup("本地翻译准备") { SetupView().frame(width: 480, height: 240) }
    }
}

struct SetupView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("苹果本地翻译准备").font(.title2)
            Text("请按苹果系统提示准备中英文离线语言包，供输入法显示英文释义。")
        }
        .padding(24)
        .translationTask(source: Locale.Language(identifier: "zh-Hans"), target: Locale.Language(identifier: "en")) { @Sendable session in
            do {
                try await session.prepareTranslation()
                print("TRANSLATION_READY")
            } catch {
                print("TRANSLATION_ERROR: \(error)")
            }
            fflush(stdout)
        }
    }
}
