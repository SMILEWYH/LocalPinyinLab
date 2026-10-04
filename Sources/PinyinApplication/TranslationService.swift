import Foundation

/// A batch-local identifier keeps response order independent of request order.
public struct TranslationRequest: Sendable, Equatable {
    public let identifier: String
    public let source: String

    public init(identifier: String, source: String) {
        self.identifier = identifier
        self.source = source
    }
}

public struct TranslationResponse: Sendable, Equatable {
    public let identifier: String?
    public let text: String

    public init(identifier: String?, text: String) {
        self.identifier = identifier
        self.text = text
    }
}

@MainActor
public protocol TranslationBackend: AnyObject {
    func translations(for requests: [TranslationRequest]) async throws -> [TranslationResponse]
}

/// A per-session, memory-only FIFO cache. A failed or cancelled batch never
/// changes the cache, and each call retains its own cache hits across suspension.
@MainActor
public final class TranslationService: CandidateTranslating {
    private let backend: any TranslationBackend
    private let cacheCapacity: Int
    private var cache: [String: String] = [:]
    private var insertionOrder: [String] = []

    public init(backend: any TranslationBackend, cacheCapacity: Int = 256) {
        precondition(cacheCapacity > 0, "Translation cache capacity must be positive")
        self.backend = backend
        self.cacheCapacity = cacheCapacity
    }

    public func translate(_ sources: [String]) async throws -> [String] {
        try Task.checkCancellation()
        // Actor reentrancy allows another batch to evict these entries while the
        // backend is running. Resolve this call against its own snapshot.
        var resolved: [String: String] = [:]
        var missing: [String] = []
        var additions: [(String, String)] = []
        var seen = Set<String>()
        for source in sources where seen.insert(source).inserted {
            if let translation = cache[source] {
                resolved[source] = translation
            } else {
                missing.append(source)
            }
        }

        if !missing.isEmpty {
            let requests = missing.enumerated().map {
                TranslationRequest(identifier: String($0.offset), source: $0.element)
            }
            let responses = try await backend.translations(for: requests)
            try Task.checkCancellation()
            let expected = Set(requests.map(\.identifier))
            var indexed: [String: String] = [:]
            for response in responses {
                guard let identifier = response.identifier,
                      expected.contains(identifier),
                      indexed[identifier] == nil,
                      !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw TranslationFailure.invalidResponse
                }
                indexed[identifier] = response.text
            }
            guard indexed.count == requests.count else {
                throw TranslationFailure.invalidResponse
            }
            for request in requests {
                guard let translation = indexed[request.identifier] else {
                    throw TranslationFailure.invalidResponse
                }
                resolved[request.source] = translation
                additions.append((request.source, translation))
            }
        }

        // Validate the complete result before committing any cache changes.
        let result = try sources.map { source in
            guard let translation = resolved[source] else {
                throw TranslationFailure.invalidResponse
            }
            return translation
        }
        for (source, translation) in additions {
            if cache[source] == nil { insertionOrder.append(source) }
            cache[source] = translation
            while insertionOrder.count > cacheCapacity {
                cache.removeValue(forKey: insertionOrder.removeFirst())
            }
        }
        return result
    }
}
