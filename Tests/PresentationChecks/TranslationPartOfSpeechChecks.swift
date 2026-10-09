import PinyinCore
import PinyinPresentation

extension PresentationChecks {
    @MainActor static func checkTranslationPartOfSpeechInference() {
        func row(_ text: String) -> CandidateRow {
            CandidateRow(candidate: Candidate(text: "词语", consumedCount: 2), translation: .ready(text))
        }
        let examples: [(String, TranslationPartOfSpeech)] = [
            ("apple", .noun), ("Beautiful", .adjective), ("quickly", .adverb), ("running", .verb)
        ]
        for (text, expected) in examples {
            let candidate = row(text)
            precondition(candidate.translationPartOfSpeech(for: .english) == expected,
                         "representative English translations must expose their inferred word class")
            precondition(candidate.translation == .ready(text) && candidate.speechText == text &&
                         candidate.translationText(for: .english) == text,
                         "annotations must never alter the stored, displayed, or spoken translation")
        }
        precondition(row(" Apple. ").translationPartOfSpeech(for: .english) == .noun,
                     "capitalization and surrounding punctuation must not change a noun annotation")
        for text in ["", " ", "123", "你好", "apple 苹果", "apple/orange", "good morning", "I love you.",
                     "run", "right", String(repeating: "a", count: 100)] {
            precondition(row(text).translationPartOfSpeech(for: .english) == nil,
                         "nonwords, phrases, sentences and uncertain isolated words must remain unannotated: \(text)")
        }
        for language in TranslationLanguage.allCases where language != .english {
            precondition(row("apple").translationPartOfSpeech(for: language) == nil,
                         "switching target language must not reuse an English part of speech")
        }
        for state: TranslationState in [.notRequired, .pending, .unavailable(.failed), .unavailable(.modelsNotInstalled)] {
            let candidate = CandidateRow(candidate: Candidate(text: "词语", consumedCount: 2), translation: state)
            precondition(candidate.translationPartOfSpeech(for: .english) == nil,
                         "loading and error copy must not be treated as translated words")
        }
        let nonHan = CandidateRow(candidate: Candidate(text: "ABC", consumedCount: 2), translation: .ready("apple"))
        precondition(nonHan.translationPartOfSpeech(for: .english) == nil,
                     "candidates that do not need translation must not acquire annotations")
    }
}
