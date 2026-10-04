import Foundation
import AVFAudio
import PinyinCore
import PinyinApplication
import PinyinInfrastructure

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
        let pending = CandidateRow(candidate: Candidate(text: "你好", consumedCount: 5))
        let hello = CandidateRow(candidate: Candidate(text: "你好", consumedCount: 5), translation: .ready("Hello"))
        let account = CandidateRow(candidate: Candidate(text: "你号", consumedCount: 5), translation: .ready("Your account"))
        precondition(pending.speechText == nil)
        precondition(CandidateRow(candidate: Candidate(text: "nihao", consumedCount: 5), translation: .ready("nihao")).speechText == nil)
        precondition(CandidateRow(candidate: Candidate(text: "你好", consumedCount: 5), translation: .ready(" ")).speechText == nil)
        precondition(CandidateRow(candidate: Candidate(text: "你好", consumedCount: 5), translation: .unavailable(.failed)).speechText == nil)
        var selected = CandidateList(rows: [hello, account])
        selected.move(by: 1)
        precondition(selected.selectedRow?.speechText == "Your account")
        var pages = CandidateList(rows: Array(repeating: hello, count: PinyinRules.pageSize) + [account])
        pages.movePage(by: 1)
        precondition(pages.selectedRow?.speechText == "Your account")
        precondition(pages.page == 1 && pages.highlighted == 0)
        precondition(pages.indexOnPage(1) == nil)
        precondition(CandidateList().selectedRow?.speechText == nil)
        for (key, flags, expected): (UInt16, KeyModifiers, Bool) in [
            (15, [.control, .shift], true), (15, [.control], false),
            (15, [.shift], false), (15, [.command, .shift], false),
            (15, [.control, .shift, .option], false), (15, [], false),
            (49, [.option], false), (49, [.control, .shift], false), (49, [], false)
        ] {
            let event = KeyStroke(code: key, characters: key == 15 ? "R" : " ", modifiers: flags)
            precondition(event.requestsSpeech == expected)
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
