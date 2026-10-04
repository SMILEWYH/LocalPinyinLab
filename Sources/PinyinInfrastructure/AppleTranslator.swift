import Foundation
import Translation
import PinyinApplication

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

    public func status() async -> LanguageAvailability.Status {
        await backend.status()
    }

    public func translate(_ sources: [String]) async throws -> [String] {
        try await service.translate(sources)
    }
}

@available(macOS 26.0, *)
@MainActor
private final class AppleTranslationBackend: TranslationBackend {
    private let source = Locale.Language(identifier: "zh-Hans")
    private let target = Locale.Language(identifier: "en")

    func status() async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: source, to: target)
    }

    func translations(for requests: [TranslationRequest]) async throws -> [TranslationResponse] {
        try Task.checkCancellation()
        // Only installed models are used; this adapter never requests a download.
        guard await status() == .installed else { throw TranslationFailure.modelsNotInstalled }
        try Task.checkCancellation()
        return try await Self.translateInstalled(requests)
    }

    // Keep the framework's non-Sendable request/session objects on the async
    // executor. Only our Sendable request and response values cross the boundary.
    nonisolated private static func translateInstalled(_ requests: [TranslationRequest]) async throws -> [TranslationResponse] {
        let source = Locale.Language(identifier: "zh-Hans")
        let target = Locale.Language(identifier: "en")
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
