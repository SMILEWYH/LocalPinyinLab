import SwiftUI
import Translation

@main
struct TranslationSetup: App {
    var body: some Scene {
        WindowGroup("本地翻译准备") { SetupView().frame(width: 480, height: 300) }
            .windowResizability(.contentSize)
    }
}

struct SetupView: View {
    @StateObject private var model = SetupModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("中英离线翻译", systemImage: "character.bubble").font(.title2)
            Text("准备语言包后，拼音候选旁即可显示英文译文。缺少语言包不影响中文输入。")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if model.isBusy { ProgressView().controlSize(.small) }
                Text(model.message).accessibilityIdentifier("translation-setup-status")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack {
                Button("重新检查") { Task { await model.checkAvailability() } }
                    .disabled(model.isBusy)
                Spacer()
                if model.isReady {
                    Button("完成") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(model.hasFailed ? "重试准备" : "准备语言包") { model.prepare() }
                        .disabled(model.isBusy || model.isUnsupported)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .task { await model.checkAvailability() }
        .translationTask(model.configuration) { @Sendable session in
            do {
                try await session.prepareTranslation()
                await model.finishedPreparation()
            } catch {
                await model.failedPreparation()
            }
        }
    }
}

@MainActor
final class SetupModel: ObservableObject {
    private enum Phase { case checking, needsPreparation, preparing, ready, failed, unsupported }
    @Published private var phase: Phase = .checking
    @Published var configuration: TranslationSession.Configuration?

    var isBusy: Bool { phase == .checking || phase == .preparing }
    var isReady: Bool { phase == .ready }
    var hasFailed: Bool { phase == .failed }
    var isUnsupported: Bool { phase == .unsupported }
    var message: String {
        switch phase {
        case .checking: return "正在检查中英离线语言包…"
        case .needsPreparation: return "尚未安装语言包。点击下方按钮，按系统提示准备。"
        case .preparing: return "正在准备，请完成系统提示并等待下载结束…"
        case .ready: return "语言包已就绪，可以关闭此窗口并继续输入。"
        case .failed: return "准备未完成。请检查网络和系统提示，然后重试。"
        case .unsupported: return "当前系统暂不支持中英翻译。中文输入仍可正常使用。"
        }
    }

    func checkAvailability() async {
        guard phase != .preparing else { return }
        phase = .checking
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: "zh-Hans"), to: Locale.Language(identifier: "en"))
        switch status {
        case .installed: phase = .ready
        case .supported: phase = .needsPreparation
        case .unsupported: phase = .unsupported
        @unknown default: phase = .failed
        }
    }

    func prepare() {
        guard !isBusy, !isReady, !isUnsupported else { return }
        phase = .preparing
        if configuration != nil { configuration?.invalidate() }
        else {
            configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "zh-Hans"), target: Locale.Language(identifier: "en"))
        }
    }

    func finishedPreparation() { phase = .ready }
    func failedPreparation() { phase = .failed }
}
