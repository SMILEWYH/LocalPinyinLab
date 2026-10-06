import Foundation
import CoreFoundation
import PinyinApplication

/// Shared with the settings app; notifications invalidate rather than carry settings.
@MainActor
public enum SpeechShortcutPreferences {
    public static let didChangeNotification = Notification.Name("local.pinyinlab.preferences.speechShortcutDidChange")
    public static let notificationObject = "local.pinyinlab.preferences"

    private static let domain = "local.pinyinlab.preferences" as CFString
    private static let shortcutKey = "speechShortcut" as CFString

    public static var shortcut: SpeechShortcut {
        _ = synchronize()
        guard let data = storedValue() as? Data,
              let shortcut = try? JSONDecoder().decode(SpeechShortcut.self, from: data) else { return .default }
        return shortcut
    }

    public static func setShortcut(_ shortcut: SpeechShortcut) throws {
        let data = try JSONEncoder().encode(shortcut)
        guard synchronize() else { throw PreferenceError.cannotSave }
        let previous = storedValue()
        CFPreferencesSetValue(shortcutKey, data as CFData, domain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard synchronize() else {
            CFPreferencesSetValue(shortcutKey, previous, domain,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            _ = synchronize()
            throw PreferenceError.cannotSave
        }
        DistributedNotificationCenter.default().postNotificationName(
            didChangeNotification, object: notificationObject, userInfo: nil, deliverImmediately: true)
    }

    private static func storedValue() -> CFPropertyList? {
        CFPreferencesCopyValue(shortcutKey, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private static func synchronize() -> Bool {
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private enum PreferenceError: LocalizedError {
        case cannotSave
        var errorDescription: String? { "无法保存朗读快捷键，请重试。" }
    }
}
