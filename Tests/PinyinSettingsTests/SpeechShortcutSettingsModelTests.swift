import PinyinApplication
import Testing
@testable import PinyinSettings

@Suite("Speech shortcut settings")
@MainActor
struct SpeechShortcutSettingsModelTests {
    @Test("Default is Command Option and drafts do not change the active shortcut")
    func editsRequireSave() throws {
        let preferences = ShortcutStore()
        let model = SpeechShortcutSettingsModel(reader: preferences.read, writer: preferences.write)
        #expect(model.savedShortcut == .default)
        #expect(model.draftModifiers == [.command, .option])
        #expect(model.draftKeyCode == nil)
        #expect(!model.canSave)

        model.setModifier(.option, enabled: false)
        model.draftKeyCode = 0
        let expected = try #require(SpeechShortcut(modifiers: .command, keyCode: 0))
        #expect(model.canSave)
        #expect(model.savedShortcut == .default)
        #expect(preferences.writeCount == 0)

        model.save()
        #expect(preferences.shortcut == expected)
        #expect(model.savedShortcut == expected)
        #expect(!model.hasUnsavedChanges)
        #expect(model.saveError == nil)
        #expect(model.saveMessage != nil)
        #expect(preferences.writeCount == 1)
    }

    @Test("A failed save preserves the active shortcut and the draft for retry")
    func failedSaveKeepsDraft() throws {
        let preferences = ShortcutStore()
        let model = SpeechShortcutSettingsModel(reader: preferences.read, writer: preferences.write)
        model.draftModifiers = [.control, .shift]
        model.draftKeyCode = 15
        let draft = try #require(model.draftShortcut)
        preferences.shouldFail = true
        model.save()

        #expect(preferences.shortcut == .default)
        #expect(model.savedShortcut == .default)
        #expect(model.draftShortcut == draft)
        #expect(model.canSave)
        #expect(model.saveError != nil)
        #expect(model.saveMessage == nil)

        preferences.shouldFail = false
        model.save()
        #expect(preferences.shortcut == draft)
        #expect(model.savedShortcut == draft)
        #expect(model.saveError == nil)
        #expect(!model.canSave)
    }

    @Test("Restoring the default only applies after saving")
    func restoreDefaultIsDraft() throws {
        let previous = try #require(SpeechShortcut(modifiers: [.control, .shift], keyCode: 15))
        let preferences = ShortcutStore(shortcut: previous)
        let model = SpeechShortcutSettingsModel(reader: preferences.read, writer: preferences.write)
        model.restoreDefault()

        #expect(model.draftShortcut == .default)
        #expect(model.isDraftDefault)
        #expect(model.savedShortcut == previous)
        #expect(preferences.shortcut == previous)
        #expect(preferences.writeCount == 0)
        #expect(model.canSave)

        model.save()
        #expect(preferences.shortcut == .default)
        #expect(model.savedShortcut == .default)
    }

    @Test("Invalid combinations cannot overwrite a saved shortcut")
    func rejectsInvalidDrafts() {
        let preferences = ShortcutStore()
        let model = SpeechShortcutSettingsModel(reader: preferences.read, writer: preferences.write)
        model.draftModifiers = .command
        #expect(model.validationMessage != nil)
        #expect(!model.canSave)
        model.save()
        #expect(preferences.writeCount == 0)

        model.draftModifiers = [.command, .option, .shift]
        model.draftKeyCode = 0
        #expect(model.validationMessage != nil)
        #expect(!model.canSave)
        model.save()
        #expect(preferences.writeCount == 0)
        #expect(model.savedShortcut == .default)
    }

    @Test("External preference changes refresh idle drafts but preserve unfinished edits")
    func externalChangesPreserveEdits() throws {
        let external = try #require(SpeechShortcut(modifiers: [.control, .shift], keyCode: 15))
        let preferences = ShortcutStore()
        let model = SpeechShortcutSettingsModel(reader: preferences.read, writer: preferences.write)
        preferences.shortcut = external
        model.refreshFromPreferences()
        #expect(model.savedShortcut == external)
        #expect(model.draftShortcut == external)
        #expect(!model.hasUnsavedChanges)

        // Even an incomplete edit must survive activating another settings window.
        model.draftModifiers = .command
        model.draftKeyCode = nil
        preferences.shortcut = .default
        model.refreshFromPreferences()
        #expect(model.savedShortcut == .default)
        #expect(model.draftModifiers == .command)
        #expect(model.draftKeyCode == nil)
        #expect(model.hasUnsavedChanges)
        #expect(model.validationMessage != nil)
        #expect(preferences.writeCount == 0)
    }
}

@MainActor
private final class ShortcutStore {
    enum Failure: Error { case unavailable }

    var shortcut: SpeechShortcut
    var shouldFail = false
    private(set) var writeCount = 0

    init(shortcut: SpeechShortcut = .default) { self.shortcut = shortcut }
    func read() -> SpeechShortcut { shortcut }
    func write(_ shortcut: SpeechShortcut) throws {
        writeCount += 1
        if shouldFail { throw Failure.unavailable }
        self.shortcut = shortcut
    }
}
