import SwiftUI
import PinyinApplication
import PinyinInfrastructure

@MainActor
final class SpeechShortcutSettingsModel: ObservableObject {
    typealias Reader = @MainActor () -> SpeechShortcut
    typealias Writer = @MainActor (SpeechShortcut) throws -> Void

    @Published private(set) var savedShortcut: SpeechShortcut
    @Published var draftModifiers: KeyModifiers { didSet { clearFeedback() } }
    @Published var draftKeyCode: UInt16? { didSet { clearFeedback() } }
    @Published private(set) var saveError: String?
    @Published private(set) var saveMessage: String?

    private let read: Reader
    private let write: Writer

    init(reader: @escaping Reader = { SpeechShortcutPreferences.shortcut },
         writer: @escaping Writer = { try SpeechShortcutPreferences.setShortcut($0) }) {
        read = reader
        write = writer
        let saved = reader()
        savedShortcut = saved
        draftModifiers = saved.modifiers
        draftKeyCode = saved.keyCode
    }

    var draftShortcut: SpeechShortcut? {
        SpeechShortcut(modifiers: draftModifiers, keyCode: draftKeyCode)
    }

    var validationMessage: String? {
        SpeechShortcut.validationMessage(modifiers: draftModifiers, keyCode: draftKeyCode)
    }

    var hasUnsavedChanges: Bool {
        draftModifiers != savedShortcut.modifiers || draftKeyCode != savedShortcut.keyCode
    }

    var canSave: Bool { hasUnsavedChanges && draftShortcut != nil }

    var isDraftDefault: Bool {
        draftModifiers == SpeechShortcut.default.modifiers && draftKeyCode == SpeechShortcut.default.keyCode
    }

    func setModifier(_ modifier: KeyModifiers, enabled: Bool) {
        if enabled { draftModifiers.insert(modifier) }
        else { draftModifiers.remove(modifier) }
    }

    func restoreDefault() {
        draftModifiers = SpeechShortcut.default.modifiers
        draftKeyCode = SpeechShortcut.default.keyCode
    }

    func save() {
        guard let shortcut = draftShortcut, hasUnsavedChanges else { return }
        do {
            try write(shortcut)
        } catch {
            saveMessage = nil
            saveError = "未能保存朗读快捷键，仍使用 \(savedShortcut.displayName)。请重试。"
            return
        }
        savedShortcut = shortcut
        saveError = nil
        saveMessage = "已保存：\(shortcut.displayName)"
    }

    /// Refresh the active value without discarding a user's unfinished edit.
    func refreshFromPreferences() {
        let preserveDraft = hasUnsavedChanges
        let saved = read()
        guard saved != savedShortcut else { return }
        savedShortcut = saved
        clearFeedback()
        if !preserveDraft {
            draftModifiers = saved.modifiers
            draftKeyCode = saved.keyCode
        }
    }

    private func clearFeedback() {
        saveError = nil
        saveMessage = nil
    }
}
