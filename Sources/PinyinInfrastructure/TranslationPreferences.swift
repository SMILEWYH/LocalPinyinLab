import Foundation
import CoreFoundation
import PinyinCore

/// The settings app and input method use the same user-level preference domain.
/// No app-group entitlement is needed: both are unsandboxed apps of this user.
@MainActor
public enum TranslationPreferences {
    public static let didChangeNotification = Notification.Name("local.pinyinlab.preferences.translationTargetLanguageDidChange")
    public static let notificationObject = "local.pinyinlab.preferences"

    private static let domain = "local.pinyinlab.preferences" as CFString
    private static let targetKey = "translationTargetLanguage" as CFString

    public static var targetLanguage: TranslationLanguage {
        // Pull changes made by another process before consulting CFPreferences'
        // local cache; neither app keeps an additional cached preference value.
        _ = synchronize()
        guard let identifier = storedValue() as? String,
              let language = TranslationLanguage(rawValue: identifier) else { return .english }
        return language
    }

    public static func setTargetLanguage(_ language: TranslationLanguage) throws {
        guard synchronize() else { throw PreferenceError.cannotSave }
        let previous = storedValue()
        CFPreferencesSetValue(targetKey, language.rawValue as CFString, domain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard synchronize() else {
            // Discard the failed in-process change as well. A failed write must
            // not look successful through a later read of this process's cache.
            CFPreferencesSetValue(targetKey, previous, domain,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            _ = synchronize()
            throw PreferenceError.cannotSave
        }
        // Treat notifications only as invalidations. Observers reread the
        // validated value above instead of accepting data carried by a sender.
        DistributedNotificationCenter.default().postNotificationName(
            didChangeNotification, object: notificationObject, userInfo: nil, deliverImmediately: true)
    }

    private static func storedValue() -> CFPropertyList? {
        CFPreferencesCopyValue(targetKey, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private static func synchronize() -> Bool {
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private enum PreferenceError: LocalizedError {
        case cannotSave
        var errorDescription: String? { "无法保存翻译目标语言，请重试。" }
    }
}
