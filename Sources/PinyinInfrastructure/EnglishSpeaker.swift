import AVFAudio
import PinyinApplication

@MainActor
public final class EnglishSpeaker: SpeechPlaying {
    private let synthesizer = AVSpeechSynthesizer()
    private lazy var voice = Self.installedVoice()

    public init() {}

    public static func installedVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.identifier.hasPrefix("com.apple.") && $0.language.hasPrefix("en-") &&
            !$0.voiceTraits.contains(.isPersonalVoice) && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        return voices.first { $0.language == "en-US" && $0.name == "Samantha" }
            ?? voices.first { $0.language == "en-US" } ?? voices.first
    }

    public static func utterance(_ text: String, voice: AVSpeechSynthesisVoice) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        return utterance
    }

    public func speak(_ text: String) -> Bool {
        stop()
        guard let voice else { return false }
        synthesizer.speak(Self.utterance(text, voice: voice))
        return true
    }

    public func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
