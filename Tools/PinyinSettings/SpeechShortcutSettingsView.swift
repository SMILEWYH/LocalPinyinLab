import SwiftUI
import PinyinApplication

struct SpeechShortcutSettingsView: View {
    @ObservedObject var model: SpeechShortcutSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("自定义朗读快捷键").font(.body.weight(.semibold))
            Text("选择 2 或 3 个键：可只选修饰键，也可搭配一个普通键。修改后点击「保存快捷键」生效。")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                modifierToggle("Command", modifier: .command, identifier: "command")
                modifierToggle("Option", modifier: .option, identifier: "option")
                modifierToggle("Control", modifier: .control, identifier: "control")
                modifierToggle("Shift", modifier: .shift, identifier: "shift")
            }
            Picker("普通键", selection: $model.draftKeyCode) {
                Text("无（只用修饰键）").tag(nil as UInt16?)
                ForEach(SpeechShortcut.keyOptions, id: \.code) { option in
                    Text(option.name).tag(Optional(option.code))
                }
            }
            .frame(maxWidth: 300)
            .accessibilityIdentifier("speech-shortcut-key")
            if let validation = model.validationMessage {
                Text(validation).font(.callout).foregroundStyle(.orange)
                    .accessibilityIdentifier("speech-shortcut-validation")
            } else if let shortcut = model.draftShortcut {
                Text("\(model.hasUnsavedChanges ? "待保存" : "当前快捷键")：\(shortcut.displayName)")
                    .font(.callout)
                    .accessibilityIdentifier("speech-shortcut-preview")
            }
            HStack(spacing: 12) {
                Button("保存快捷键") { model.save() }
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("speech-shortcut-save")
                Button("恢复默认") { model.restoreDefault() }
                    .disabled(model.isDraftDefault)
                    .accessibilityIdentifier("speech-shortcut-reset")
            }
            if let error = model.saveError {
                Text(error).font(.callout).foregroundStyle(.orange)
                    .accessibilityIdentifier("speech-shortcut-save-error")
            } else if let message = model.saveMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("speech-shortcut-save-status")
            }
            Text("仅在候选框显示、当前候选已有完整译文时有效。只用修饰键时，按下组合后全部松开才朗读；期间按下其他键会取消。快捷键仍可能与前台软件冲突。")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("speech-shortcut-behavior")
        }
    }

    private func modifierToggle(_ title: String, modifier: KeyModifiers, identifier: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { model.draftModifiers.contains(modifier) },
            set: { model.setModifier(modifier, enabled: $0) }))
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("speech-shortcut-modifier-" + identifier)
    }
}
