import Foundation
import PinyinApplication
import PinyinCore

/// Async access to a persistent worker. All live process/pipe operations run on
/// one dedicated queue; they never block the input service's main actor.
public final class PinyinSession: @unchecked Sendable {
    public static let shared = PinyinSession(
        workerRoot: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Worker")
    )
    private let queue = DispatchQueue(label: "local.pinyinlab.worker", qos: .userInteractive)
    private let worker: PinyinWorker

    public init(workerRoot: URL) { worker = PinyinWorker(workerRoot: workerRoot) }

    // Enqueued work retains self. Deinitialization therefore happens only after
    // the final operation has released the worker's sole owner.
    deinit { worker.stop() }

    public func warm() {
        queue.async { [self] in
            do { try worker.start() } catch { worker.stop() }
        }
    }

    public func candidates(for pinyin: String, context: String = "") async throws -> [Candidate] {
        guard PinyinRules.isValid(pinyin) else { throw PinyinWorkerError.invalidInput }
        let cancellation = QueryCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    do {
                        try cancellation.check()
                        let result = try worker.candidates(for: pinyin, context: context,
                                                          checkCancellation: cancellation.check)
                        try cancellation.check()
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    public func shutdown() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                worker.stop()
                continuation.resume()
            }
        }
    }
}

// Declare the UI-facing port separately: its main-actor requirement does not
// make this queue-owned infrastructure class or its process state main-actor bound.
extension PinyinSession: CandidateProviding {}

private final class QueryCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
    }

    func check() throws {
        lock.lock()
        let value = cancelled
        lock.unlock()
        if value { throw CancellationError() }
    }
}
