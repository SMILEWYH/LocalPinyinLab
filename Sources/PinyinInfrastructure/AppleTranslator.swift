import Foundation
import Translation
import PinyinApplication
import PinyinCore

@available(macOS 26.0, *)
@MainActor
public final class AppleTranslator: CandidateTranslating {
    private let backend: AppleTranslationBackend
    private let service: TranslationService

    public init() {
        let backend = AppleTranslationBackend()
        self.backend = backend
        service = TranslationService(backend: backend)
    }

    public func status(for language: TranslationLanguage) async -> LanguageAvailability.Status {
        await backend.status(for: language)
    }

    public func translate(_ sources: [String], to language: TranslationLanguage) async throws -> [String] {
        try await service.translate(sources, to: language)
    }
}

@available(macOS 26.0, *)
@MainActor
private final class AppleTranslationBackend: TranslationBackend {
    private let source = Locale.Language(identifier: "zh-Hans")

    func status(for language: TranslationLanguage) async -> LanguageAvailability.Status {
        await AppleTranslationPolicy.availability().status(from: source, to: Locale.Language(identifier: language.localeIdentifier))
    }

    func translations(for requests: [TranslationRequest], to language: TranslationLanguage) async throws -> [TranslationResponse] {
        try Task.checkCancellation()
        // Only installed models are used; this adapter never requests a download.
        guard await status(for: language) == .installed else { throw TranslationFailure.modelsNotInstalled }
        try Task.checkCancellation()
        return try await Self.translateInstalled(requests, to: language)
    }

    // Keep the framework's non-Sendable request/session objects on the async
    // executor. Only our Sendable request and response values cross the boundary.
    nonisolated private static func translateInstalled(_ requests: [TranslationRequest],
                                                      to language: TranslationLanguage) async throws -> [TranslationResponse] {
        let source = Locale.Language(identifier: "zh-Hans")
        let target = Locale.Language(identifier: language.localeIdentifier)
        let session: TranslationSession
        if #available(macOS 26.4, *) {
            session = TranslationSession(installedSource: source, target: target, preferredStrategy: .lowLatency)
        } else {
            session = TranslationSession(installedSource: source, target: target)
        }
        let batch = requests.map {
            TranslationSession.Request(sourceText: $0.source, clientIdentifier: $0.identifier)
        }
        let responses = try await session.translations(from: batch)
        try Task.checkCancellation()
        return responses.map { TranslationResponse(identifier: $0.clientIdentifier, text: $0.targetText) }
    }
}
