import Foundation
import Translation

@available(macOS 26.0, *)
@MainActor
final class AppleTranslator {
    private let source = Locale.Language(identifier: "zh-Hans")
    private let target = Locale.Language(identifier: "en")
    private var cache: [String: String] = [:]
    private var order: [String] = []

    func status() async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: source, to: target)
    }

    // 仅使用已安装模型，不触发下载或询问用户授权。
    func translate(_ samples: [String]) async throws -> [String] {
        try Task.checkCancellation()
        var seen = Set<String>()
        let missing = samples.filter { cache[$0] == nil && seen.insert($0).inserted }
        if missing.isEmpty { return samples.map { cache[$0]! } }
        guard await status() == .installed else { throw TranslationError.notInstalled }
        try Task.checkCancellation()
        let session: TranslationSession
        if #available(macOS 26.4, *) {
            session = TranslationSession(installedSource: source, target: target, preferredStrategy: .lowLatency)
        } else {
            session = TranslationSession(installedSource: source, target: target)
        }
        let requests = missing.enumerated().map {
            TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
        }
        let responses = try await session.translations(from: requests)
        try Task.checkCancellation()
        let indexed = Dictionary(uniqueKeysWithValues: responses.compactMap { response -> (String, String)? in
            guard let id = response.clientIdentifier else { return nil }
            return (id, response.targetText)
        })
        var resolved = cache
        for (index, source) in missing.enumerated() {
            guard let text = indexed[String(index)], !text.isEmpty else { throw TranslationError.internalError }
            resolved[source] = text
            cache[source] = text
            order.removeAll { $0 == source }
            order.append(source)
        }
        // 仅内存缓存，不写磁盘或日志；超出上限淘汰最早条目。
        while order.count > 256 { cache.removeValue(forKey: order.removeFirst()) }
        return samples.map { resolved[$0]! }
    }
}
