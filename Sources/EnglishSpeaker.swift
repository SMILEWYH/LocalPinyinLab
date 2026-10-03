import AppKit
import AVFAudio

@MainActor
final class EnglishSpeaker {
    private let synthesizer = AVSpeechSynthesizer()
    private lazy var voice = Self.installedVoice()

    static func installedVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.identifier.hasPrefix("com.apple.") && $0.language.hasPrefix("en-") &&
            !$0.voiceTraits.contains(.isPersonalVoice) && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        return voices.first { $0.language == "en-US" && $0.name == "Samantha" }
            ?? voices.first { $0.language == "en-US" } ?? voices.first
    }

    static func matches(_ event: NSEvent) -> Bool {
        event.keyCode == 15 && event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.control, .shift]
    }

    static func selectedText(rows: [Candidate], page: Int, highlighted: Int) -> String? {
        guard page >= 0, (0..<9).contains(highlighted) else { return nil }
        let index = page * 9 + highlighted
        guard rows.indices.contains(index) else { return nil }
        return rows[index].speechText
    }

    static func utterance(_ text: String, voice: AVSpeechSynthesisVoice) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        return utterance
    }

    func speak(_ text: String) -> Bool {
        stop()
        guard let voice else { return false }
        synthesizer.speak(Self.utterance(text, voice: voice))
        return true
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
