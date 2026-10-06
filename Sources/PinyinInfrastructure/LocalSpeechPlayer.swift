import AVFAudio
import Foundation
import PinyinApplication
import PinyinCore

@MainActor
public final class LocalSpeechPlayer: SpeechPlaying {
    private let synthesizer = AVSpeechSynthesizer()

    public init() {}

    public static func installedVoice(for language: TranslationLanguage) -> AVSpeechSynthesisVoice? {
        let languageCode = Locale.Language(identifier: language.localeIdentifier).languageCode
        // Refresh on every request so newly installed voices become available
        // without restarting the input method. Never fall back to another language.
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.identifier.hasPrefix("com.apple.") &&
            Locale.Language(identifier: $0.language).languageCode == languageCode &&
            !$0.voiceTraits.contains(.isPersonalVoice) && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        if language == .english, let samantha = voices.first(where: { $0.language == "en-US" && $0.name == "Samantha" }) {
            return samantha
        }
        return voices.first { $0.language == language.speechLanguageIdentifier } ?? voices.first
    }

    public static func utterance(_ text: String, voice: AVSpeechSynthesisVoice) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        return utterance
    }

    public func speak(_ text: String, language: TranslationLanguage) -> Bool {
        stop()
        guard let voice = Self.installedVoice(for: language) else { return false }
        synthesizer.speak(Self.utterance(text, voice: voice))
        return true
    }

    public func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
