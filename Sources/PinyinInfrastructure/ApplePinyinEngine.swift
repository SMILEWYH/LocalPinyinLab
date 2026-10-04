import Foundation
import PinyinCore

/// An independent query session for command-line diagnostics and integration tests.
/// It shares the production transport's timeouts, frame limits and child cleanup.
public struct ApplePinyinEngine: Sendable {
    public typealias EngineError = PinyinWorkerError
    public let workerRoot: URL

    public init(workerRoot: URL) { self.workerRoot = workerRoot }

    public func candidates(for pinyin: String, context: String = "") throws -> [Candidate] {
        let worker = PinyinWorker(workerRoot: workerRoot)
        defer { worker.stop() }
        return try worker.candidates(for: pinyin, context: context)
    }
}
