import AppKit
import SwiftUI

struct UsageGuideView: View {
    @ObservedObject var model: LanguagePacksModel
    let openLanguagePacks: () -> Void
    @StateObject private var keyboardSettings = KeyboardSettingsModel()

    var body: some View {
        SettingsPageContent(title: "使用说明", subtitle: "添加输入法，了解常用键盘操作。", identifier: "settings-page-guide") {
            SettingsCard(title: "开始使用", symbol: "keyboard") {
                Text("在「系统设置 → 键盘 → 文本输入 → 编辑」中添加「拼音」，然后切换到拼音输入法。")
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Button("打开键盘设置") { keyboardSettings.open() }
                        .accessibilityIdentifier("guide-open-keyboard-settings")
                    Button("选择翻译语言", action: openLanguagePacks)
                        .accessibilityIdentifier("guide-open-language-packs")
                }
                if let error = keyboardSettings.errorMessage {
                    Text(error).font(.callout).foregroundStyle(.orange)
                        .accessibilityIdentifier("guide-keyboard-settings-error")
                }
            }
            SettingsCard(title: "中英与大小写", symbol: "capslock") {
                GuideRow(keys: "Caps Lock", description: "灯灭输入中文拼音，灯亮输入英文。英文默认小写，按住 Shift 可临时输入大写。",
                         identifier: "guide-shortcut-mode")
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("先按住 Shift，再按 Caps Lock").font(.body.weight(.semibold))
                        .accessibilityIdentifier("guide-shortcut-uppercase")
                    Text("进入英文并锁定大写；再次按相同顺序操作，恢复英文小写。两种英文状态都保持 Caps Lock 灯亮。")
                    Text("按键顺序很重要：先按 Caps Lock 再按 Shift，只会先切换中英。单按 Caps Lock 灭灯返回中文，也会解除大写锁定。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Divider()
                GuideRow(keys: "Control + Shift + Space", description: "切换中文与英文，同时同步 Caps Lock 指示灯。",
                         identifier: "guide-shortcut-toggle")
            }
            SettingsCard(title: "选择候选与翻页", symbol: "list.number") {
                GuideRow(keys: "空格 / 1–9", description: "空格确认当前候选；数字键选择本页对应序号的候选。", identifier: "guide-shortcut-select")
                Divider()
                GuideRow(keys: "↑ / ↓", description: "移动当前选中候选。", identifier: "guide-shortcut-highlight")
                Divider()
                GuideRow(keys: "← / →", description: "上一页 / 下一页，也支持 Page Up / Page Down。首页和末页不循环翻页。", identifier: "guide-shortcut-page")
            }
            SettingsCard(title: "编辑与提交", symbol: "text.cursor") {
                GuideRow(keys: "Backspace", description: "删除待转换拼音。", identifier: "guide-shortcut-backspace")
                Divider()
                GuideRow(keys: "Shift + ←", description: "撤回已选中的上一段中文，继续修改拼音。", identifier: "guide-shortcut-undo")
                Divider()
                GuideRow(keys: "Esc", description: "取消当前组合内容。", identifier: "guide-shortcut-cancel")
                Divider()
                GuideRow(keys: "回车", description: "提交已选中文与剩余拼音，不额外插入换行。", identifier: "guide-shortcut-return")
            }
            SettingsCard(title: "目标语言朗读", symbol: "speaker.wave.2") {
                Text(model.voiceMessage).font(.headline).accessibilityIdentifier("speech-voice-status")
                Text("选中已有\(model.targetLanguage.displayName)译文的候选后，按 Control + Shift + R 朗读。")
                    .accessibilityIdentifier("guide-shortcut-speak")
                Text("在左侧「语言包」中选择目标语言并准备对应语言包，朗读会跟随所选语言。译文在后台加载，不影响中文选词。")
                    .font(.callout).foregroundStyle(.secondary)
                if model.voiceName == nil {
                    Text("请在系统辅助功能的语音设置中添加对应语言的声音；未安装时会提示朗读不可用。")
                        .foregroundStyle(.secondary)
                }
                Button("打开辅助功能设置") { model.openSpeechSettings() }
                    .accessibilityIdentifier("speech-open-settings")
                if let error = model.speechSettingsError {
                    Text(error).font(.callout).foregroundStyle(.orange)
                        .accessibilityIdentifier("speech-settings-error")
                }
            }
        }
    }
}

@MainActor
private final class KeyboardSettingsModel: ObservableObject {
    @Published private(set) var errorMessage: String?

    func open() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"),
              NSWorkspace.shared.open(url) else {
            errorMessage = "未能打开键盘设置。请手动打开「系统设置 → 键盘 → 文本输入 → 编辑」，然后添加「拼音」。"
            return
        }
        errorMessage = nil
    }
}

private struct GuideRow: View {
    let keys: String
    let description: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(keys).font(.body.weight(.semibold)).accessibilityIdentifier(identifier)
            Text(description).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
