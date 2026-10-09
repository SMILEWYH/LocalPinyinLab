import Foundation
import NaturalLanguage
import PinyinCore

package enum TranslationPartOfSpeech: String, Sendable {
    case noun = "n."
    case verb = "v."
    case adjective = "adj."
    case adverb = "adv."
    case pronoun = "pron."
    case determiner = "det."
    case preposition = "prep."
    case conjunction = "conj."
    case number = "num."

    package var abbreviation: String { rawValue }

    package var localizedName: String {
        switch self {
        case .noun: return "名词"
        case .verb: return "动词"
        case .adjective: return "形容词"
        case .adverb: return "副词"
        case .pronoun: return "代词"
        case .determiner: return "限定词"
        case .preposition: return "介词"
        case .conjunction: return "连词"
        case .number: return "数词"
        }
    }

    fileprivate init?(tag: NLTag) {
        switch tag {
        case .noun: self = .noun
        case .verb: self = .verb
        case .adjective: self = .adjective
        case .adverb: self = .adverb
        case .pronoun: self = .pronoun
        case .determiner: self = .determiner
        case .preposition: self = .preposition
        case .conjunction: self = .conjunction
        case .number: self = .number
        // Isolated adjectives such as "right" and "well" can receive very
        // confident interjection tags. Omit these ambiguous annotations.
        default: return nil
        }
    }
}

package protocol TranslationPartOfSpeechProviding: Sendable {
    func annotations(for rows: [CandidateRow], language: TranslationLanguage) async -> [TranslationPartOfSpeech?]
}

/// Optional display metadata, never part of committed or spoken text. The
/// system model infers one lexical class; it does not enumerate dictionary senses.
package actor EnglishPartOfSpeech: TranslationPartOfSpeechProviding {
    package static let shared = EnglishPartOfSpeech()
    // Lazy initialization runs on this actor, including the system model's first load.
    private lazy var tagger = NLTagger(tagSchemes: [.lexicalClass])
    private lazy var available = NLTagger.availableTagSchemes(for: .word, language: .english).contains(.lexicalClass)
    private struct Entry { let annotation: TranslationPartOfSpeech? }
    private var cache: [String: Entry] = [:]
    private var insertionOrder: [String] = []

    package func annotations(for rows: [CandidateRow], language: TranslationLanguage) -> [TranslationPartOfSpeech?] {
        rows.map { row in
            guard !Task.isCancelled, language == .english, row.needsTranslation,
                  case .ready(let text) = row.translation else { return nil }
            return annotation(for: text)
        }
    }

    private func annotation(for text: String) -> TranslationPartOfSpeech? {
        // Bound work and cache entries. Phrases, sentences, mixed scripts and
        // compounds have no single reliable word class and keep their raw text.
        guard available, text.utf8.prefix(81).count <= 80 else { return nil }
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
        guard !word.isEmpty, word.utf8.count <= 64,
              word.utf8.allSatisfy({ (97...122).contains($0) }) else { return nil }
        if let entry = cache[word] { return entry.annotation }
        tagger.string = word
        tagger.setLanguage(.english, range: word.startIndex..<word.endIndex)
        let hypotheses = tagger.tagHypotheses(at: word.startIndex, unit: .word,
                                             scheme: .lexicalClass, maximumCount: 1).0
        let best = hypotheses.max { $0.value < $1.value }
        let annotation = best.flatMap { $0.value >= 0.75 ? TranslationPartOfSpeech(tag: NLTag(rawValue: $0.key)) : nil }
        tagger.string = nil
        cache[word] = Entry(annotation: annotation)
        insertionOrder.append(word)
        if insertionOrder.count > 256 { cache.removeValue(forKey: insertionOrder.removeFirst()) }
        return annotation
    }
}
