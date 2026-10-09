import SwiftUI
import PinyinCore

struct LanguagePacksView: View {
    @ObservedObject var model: LanguagePacksModel
    @StateObject private var removal = LanguagePackRemovalPresentation()

    var body: some View {
        SettingsPageContent(title: "语言包", subtitle: "选择候选译文和朗读使用的目标语言。", identifier: "settings-page-language-packs") {
            SettingsCard(title: "目标语言", symbol: "globe", headerAction: {
                Button(model.isCheckingAll ? "取消检查" : "检查全部语言包") {
                    if model.isCheckingAll { model.cancelAvailabilityCheck() }
                    else { Task { await model.checkAllAvailability() } }
                }
                .accessibilityIdentifier(model.isCheckingAll ? "language-packs-cancel" : "language-packs-refresh")
            }) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 7) {
                    ForEach(TranslationLanguage.allCases, id: \.rawValue) { language in
                        languageButton(language)
                    }
                }
                if let error = model.selectionError {
                    Text(error).font(.callout).foregroundStyle(.orange)
                        .accessibilityIdentifier("translation-language-selection-error")
                }
                if let error = model.scanError {
                    Text(error).font(.callout).foregroundStyle(.orange)
                        .accessibilityIdentifier("language-packs-scan-error")
                }
            }
            SettingsCard(title: "中文 → \(model.targetLanguage.displayName)", symbol: "character.bubble", headerAction: {
                if model.isReady {
                    Button("删除语言包…", role: .destructive) {
                        removal.language = model.targetLanguage
                        removal.isPresented = true
                    }
                    .buttonStyle(.bordered).disabled(!model.canRequestRemoval)
                    .help("在系统设置中仅移除\(model.targetLanguage.displayName)，保留中文语言包。")
                    .accessibilityIdentifier("language-packs-remove")
                } else {
                    Button("准备语言包") { model.prepare() }
                        .buttonStyle(.borderedProminent).disabled(!model.canPrepare)
                        .help("打开系统「翻译语言」列表，自行选择所需语言下载。")
                        .accessibilityIdentifier("language-packs-prepare")
                }
            }) {
                HStack(alignment: .top, spacing: 12) {
                    if model.isBusy {
                        ProgressView().controlSize(.small).frame(width: 24, height: 24)
                    } else {
                        Image(systemName: model.symbol).font(.title2)
                            .foregroundStyle(model.isReady ? Color.green : Color.secondary)
                            .frame(width: 24).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.message).font(.headline).accessibilityIdentifier("language-packs-status")
                        Text(model.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("language-packs-detail")
                    }
                }
                if let error = model.preparationSettingsError {
                    Text(error).font(.callout).foregroundStyle(.orange)
                        .accessibilityIdentifier("language-packs-preparation-error")
                }
                if let error = model.removalSettingsError {
                    Text(error).font(.callout).foregroundStyle(.orange)
                        .accessibilityIdentifier("language-packs-removal-error")
                }
            }
            SettingsCard(title: "关于语言包", symbol: "info.circle") {
                Text("语言包由 macOS 管理。首次准备可能需要联网下载；下载完成后，候选翻译在本机运行。")
            }
        }
        .alert("删除\(removal.language?.displayName ?? "")语言包", isPresented: $removal.isPresented,
               presenting: removal.language) { language in
            Button("打开翻译语言") { model.openRemovalSettings(for: language) }
                .accessibilityIdentifier("language-packs-open-system-removal")
            Button("取消", role: .cancel) {}
        } message: { language in
            Text("将在系统设置中打开「翻译语言」。请仅点按「\(language.displayName)」旁的「移除」，保留中文语言包。\n\n该语言包由系统共享，移除后其他 App 也无法使用它进行离线翻译。返回此页面后会自动更新安装状态。")
        }
    }

    private func languageButton(_ language: TranslationLanguage) -> some View {
        let selected = language == model.targetLanguage
        let status = model.statuses[language] ?? .unknown
        let installationStatus = model.statusText(for: language)
        return Button { model.selectLanguage(language) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(language.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                HStack(spacing: 4) {
                    Label(installationStatus, systemImage: statusSymbol(status))
                        .font(.caption)
                        .foregroundStyle(status == .installed ? Color.green : Color.secondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    if selected {
                        Text("当前使用")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .fixedSize()
                    }
                }
                .frame(height: 17)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(LanguageCardButtonStyle(selected: selected))
        .help(language.nativeName + " · " + installationStatus + (selected ? " · 当前使用" : ""))
        .accessibilityLabel(language.displayName + "，" + language.nativeName)
        .accessibilityValue(installationStatus + (selected ? "，当前使用" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("translation-language-" + language.rawValue)
    }

    private func statusSymbol(_ status: LanguagePacksModel.PackStatus) -> String {
        switch status {
        case .installed: "checkmark.circle.fill"
        case .notInstalled: "arrow.down.circle"
        case .checking: "ellipsis.circle"
        case .unsupported: "xmark.circle"
        case .unknown: "questionmark.circle"
        }
    }
}

@MainActor
private final class LanguagePackRemovalPresentation: ObservableObject {
    @Published var language: TranslationLanguage?
    @Published var isPresented = false
}

private struct LanguageCardButtonStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(selected ? Color.accentColor.opacity(0.06) : Color(nsColor: .quaternaryLabelColor).opacity(0.16),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.35),
                                  lineWidth: selected ? 2 : 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.5)
    }
}
