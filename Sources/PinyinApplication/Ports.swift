import Foundation
import PinyinCore

// Implementations live at the system boundary; the application never imports IMK/AppKit.
@MainActor public protocol CandidateProviding: AnyObject {
    func warm()
    func candidates(for pinyin: String, context: String) async throws -> [Candidate]
}

@MainActor public protocol CandidateTranslating: AnyObject {
    /// Returns one result per source, preserving order. Partial batches must throw.
    func translate(_ sources: [String], to language: TranslationLanguage) async throws -> [String]
}

public enum TranslationFailure: Error { case modelsNotInstalled, invalidResponse }

@MainActor public protocol SpeechPlaying: AnyObject {
    func speak(_ text: String, language: TranslationLanguage) -> Bool
    func stop()
}

@MainActor public protocol InputHost: AnyObject {
    func precedingContext() -> String
    func setMarkedText(_ text: String)
    func commit(_ text: String)
}

public struct CandidatePresentation {
    public let rows: [CandidateRow]
    public let markedText: String
    public let highlighted: Int
    public let page: Int
    public let totalPages: Int
    public let status: String?
    public let translationLanguage: TranslationLanguage

    public init(candidates: CandidateList, markedText: String, status: String? = nil,
                translationLanguage: TranslationLanguage = .english) {
        rows = candidates.visibleRows
        highlighted = candidates.highlighted
        page = candidates.page
        totalPages = candidates.totalPages
        self.markedText = markedText
        self.status = status
        self.translationLanguage = translationLanguage
    }
}

@MainActor public protocol CandidatePresenting: AnyObject {
    func show(_ presentation: CandidatePresentation)
    func showLoading(pinyin: String)
    func showModeStatus(mode: InputMode)
    func showCaseStatus(uppercaseLocked: Bool)
    func hide()
}
