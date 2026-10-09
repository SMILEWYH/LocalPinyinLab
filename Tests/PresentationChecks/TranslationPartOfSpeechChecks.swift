import PinyinCore
import PinyinPresentation

extension PresentationChecks {
    @MainActor static func checkTranslationPartOfSpeechInference() async {
        func row(_ text: String) -> CandidateRow {
            CandidateRow(candidate: Candidate(text: "词语", consumedCount: 2), translation: .ready(text))
        }
        func infer(_ row: CandidateRow, language: TranslationLanguage = .english) async -> TranslationPartOfSpeech? {
            await EnglishPartOfSpeech.shared.annotations(for: [row], language: language)[0]
        }
        let examples: [(String, TranslationPartOfSpeech)] = [
            ("apple", .noun), ("Beautiful", .adjective), ("quickly", .adverb), ("running", .verb)
        ]
        for (text, expected) in examples {
            let candidate = row(text)
            let inferred = await infer(candidate)
            precondition(inferred == expected,
                         "representative English translations must expose their inferred word class")
            precondition(candidate.translation == .ready(text) && candidate.speechText == text &&
                         candidate.translationText(for: .english) == text,
                         "annotations must never alter the stored, displayed, or spoken translation")
        }
        let trimmed = await infer(row(" Apple. "))
        precondition(trimmed == .noun,
                     "capitalization and surrounding punctuation must not change a noun annotation")
        for text in ["", " ", "123", "你好", "apple 苹果", "apple/orange", "good morning", "I love you.",
                     "run", "right", String(repeating: "a", count: 100)] {
            let inferred = await infer(row(text))
            precondition(inferred == nil,
                         "nonwords, phrases, sentences and uncertain isolated words must remain unannotated: \(text)")
        }
        for language in TranslationLanguage.allCases where language != .english {
            let inferred = await infer(row("apple"), language: language)
            precondition(inferred == nil,
                         "switching target language must not reuse an English part of speech")
        }
        for state: TranslationState in [.notRequired, .pending, .unavailable(.failed), .unavailable(.modelsNotInstalled)] {
            let candidate = CandidateRow(candidate: Candidate(text: "词语", consumedCount: 2), translation: state)
            let inferred = await infer(candidate)
            precondition(inferred == nil,
                         "loading and error copy must not be treated as translated words")
        }
        let nonHan = CandidateRow(candidate: Candidate(text: "ABC", consumedCount: 2), translation: .ready("apple"))
        let nonHanAnnotation = await infer(nonHan)
        precondition(nonHanAnnotation == nil,
                     "candidates that do not need translation must not acquire annotations")
    }
}
