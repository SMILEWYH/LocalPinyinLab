/// These are selectable targets, not a promise that every macOS version has a
/// translation model or a local speech voice for each language.
public enum TranslationLanguage: String, CaseIterable, Sendable, Codable, Hashable {
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case portuguese = "pt-BR"
    case italian = "it"
    case russian = "ru"
    case arabic = "ar"
    case hindi = "hi"
    case thai = "th"
    case vietnamese = "vi"
    case indonesian = "id"
    case turkish = "tr"

    public var localeIdentifier: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: "英语"
        case .japanese: "日语"
        case .korean: "韩语"
        case .french: "法语"
        case .german: "德语"
        case .spanish: "西班牙语"
        case .portuguese: "葡萄牙语（巴西）"
        case .italian: "意大利语"
        case .russian: "俄语"
        case .arabic: "阿拉伯语"
        case .hindi: "印地语"
        case .thai: "泰语"
        case .vietnamese: "越南语"
        case .indonesian: "印度尼西亚语"
        case .turkish: "土耳其语"
        }
    }

    public var nativeName: String {
        switch self {
        case .english: "English"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        case .portuguese: "Português (Brasil)"
        case .italian: "Italiano"
        case .russian: "Русский"
        case .arabic: "العربية"
        case .hindi: "हिन्दी"
        case .thai: "ไทย"
        case .vietnamese: "Tiếng Việt"
        case .indonesian: "Bahasa Indonesia"
        case .turkish: "Türkçe"
        }
    }

    public var speechLanguageIdentifier: String {
        switch self {
        case .english: "en-US"
        case .japanese: "ja-JP"
        case .korean: "ko-KR"
        case .french: "fr-FR"
        case .german: "de-DE"
        case .spanish: "es-ES"
        case .portuguese: "pt-BR"
        case .italian: "it-IT"
        case .russian: "ru-RU"
        case .arabic: "ar-001"
        case .hindi: "hi-IN"
        case .thai: "th-TH"
        case .vietnamese: "vi-VN"
        case .indonesian: "id-ID"
        case .turkish: "tr-TR"
        }
    }
}
