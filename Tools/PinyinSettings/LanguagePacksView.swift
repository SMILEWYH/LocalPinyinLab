import SwiftUI
import PinyinCore

struct LanguagePacksView: View {
    @ObservedObject var model: LanguagePacksModel

    var body: some View {
        SettingsPageContent(title: "语言包", subtitle: "选择候选译文和朗读使用的目标语言。", identifier: "settings-page-language-packs") {
            SettingsCard(title: "目标语言", symbol: "globe", headerAction: {
                Button(model.isCheckingAll ? "正在检查全部…" : "检查全部语言包") {
                    Task { await model.checkAllAvailability() }
                }
                .disabled(model.isCheckingAll || model.isPreparing)
                .accessibilityIdentifier("language-packs-refresh")
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
            }
            SettingsCard(title: "中文 → \(model.targetLanguage.displayName)", symbol: "character.bubble") {
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
                if !model.isReady {
                    Divider().padding(.vertical, 4)
                    HStack {
                        Spacer()
                        Button(model.phase == .failed ? "重试准备" : "准备语言包") { model.prepare() }
                            .buttonStyle(.borderedProminent).disabled(!model.canPrepare)
                            .accessibilityIdentifier("language-packs-prepare")
                    }
                }
            }
            SettingsCard(title: "关于语言包", symbol: "info.circle") {
                Text("语言包由 macOS 管理。首次准备可能需要联网下载；下载完成后，候选翻译在本机运行。")
                Text("翻译语言包与朗读声音分别由系统管理。此页面只在你点击「准备语言包」后开始准备；没有语言包，也能正常输入中文。")
                    .foregroundStyle(.secondary)
            }
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
        .disabled(model.isPreparing)
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
