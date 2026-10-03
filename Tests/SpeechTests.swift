import AppKit
import AVFAudio

private final class AudioResult: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: UInt64 = 0
    private var finished = false
    func receive(_ buffer: AVAudioBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        frames += UInt64(pcm.frameLength)
        if pcm.frameLength == 0 { finished = true }
    }
    var snapshot: (UInt64, Bool) {
        lock.lock(); defer { lock.unlock() }
        return (frames, finished)
    }
}

@main
struct SpeechTests {
    @MainActor static func main() {
        let pending = Candidate(text: "你好", translation: "等待本地翻译")
        let hello = Candidate(text: "你好", translation: "Hello", translationReady: true)
        let account = Candidate(text: "你号", translation: "Your account", translationReady: true)
        precondition(pending.speechText == nil)
        precondition(Candidate(text: "nihao", translation: "nihao", translationReady: true).speechText == nil)
        precondition(Candidate(text: "你好", translation: " ", translationReady: true).speechText == nil)
        precondition(Candidate(text: "你好", translation: "本地翻译暂不可用").speechText == nil)
        precondition(EnglishSpeaker.selectedText(rows: [hello, account], page: 0, highlighted: 1) == "Your account")
        let pages = Array(repeating: hello, count: 9) + [account]
        precondition(EnglishSpeaker.selectedText(rows: pages, page: 1, highlighted: 0) == "Your account")
        precondition(EnglishSpeaker.selectedText(rows: [hello], page: 1, highlighted: 0) == nil)
        for (key, flags, expected): (UInt16, NSEvent.ModifierFlags, Bool) in [
            (15, [.control, .shift], true), (15, [.control], false),
            (15, [.shift], false), (15, [.command, .shift], false),
            (15, [.control, .shift, .option], false), (15, [], false),
            (49, [.option], false), (49, [.control, .shift], false), (49, [], false)
        ] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: key == 15 ? "R" : " ",
                charactersIgnoringModifiers: key == 15 ? "r" : " ", isARepeat: false, keyCode: key)!
            precondition(EnglishSpeaker.matches(event) == expected)
        }
        print("PASS: highlighted row/page mapping, pending/error/raw-pinyin rejection, exact Control+Shift+R; Space combinations excluded")
        guard let voice = EnglishSpeaker.installedVoice() else { fatalError("No installed Apple English voice") }
        print("Installed voice: \(voice.identifier), \(voice.language)")
        let synthesizer = AVSpeechSynthesizer()
        let result = AudioResult()
        // Render synthetic English into memory, not the speakers or a microphone.
        synthesizer.write(EnglishSpeaker.utterance("Hello. What time is it in Beijing?", voice: voice)) { result.receive($0) }
        let deadline = Date().addingTimeInterval(20)
        while !result.snapshot.1 && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        let (frames, done) = result.snapshot
        precondition(done && frames > 0, "Local synthesis did not produce complete audio")
        print("PASS: Apple English synthesis completed, \(frames) PCM frames; no speaker playback in this test")
    }
}
