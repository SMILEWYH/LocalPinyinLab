import Foundation
import Translation
import PinyinCore

/// Keep availability checks and user-requested preparation on the same models
/// as the installed-only translation session.
@available(macOS 26.0, *)
@MainActor
public enum AppleTranslationPolicy {
    // Transfer this fresh non-Sendable instance to the SDK's async status calls.
    public static func availability() -> sending LanguageAvailability {
        if #available(macOS 26.4, *) {
            return LanguageAvailability(preferredStrategy: .lowLatency)
        }
        return LanguageAvailability()
    }

    public static func configuration(to language: TranslationLanguage) -> TranslationSession.Configuration {
        let source = Locale.Language(identifier: "zh-Hans")
        let target = Locale.Language(identifier: language.localeIdentifier)
        if #available(macOS 26.4, *) {
            return TranslationSession.Configuration(source: source, target: target, preferredStrategy: .lowLatency)
        }
        return TranslationSession.Configuration(source: source, target: target)
    }
}
