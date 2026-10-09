import Foundation
import PinyinApplication
import PinyinCore

/// Async access to a persistent worker. All live process/pipe operations run on
/// one dedicated queue; they never block the input service's main actor.
public final class PinyinSession: @unchecked Sendable {
    public static let shared = PinyinSession(
        workerRoot: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Worker"),
        usageFileURL: CandidateUsageStore.defaultFileURL
    )
    private let queue = DispatchQueue(label: "local.pinyinlab.worker", qos: .userInteractive)
    private let worker: PinyinWorker
    private let usage: CandidateUsageStore?
    private let warmup = WorkerWarmup()

    /// Independent diagnostic sessions do not read or modify personal history.
    public init(workerRoot: URL, usageFileURL: URL? = nil) {
        worker = PinyinWorker(workerRoot: workerRoot)
        usage = usageFileURL.map { CandidateUsageStore(fileURL: $0) }
    }

    package init(workerRoot: URL, usageFileURL: URL, persistenceQueue: DispatchQueue) {
        worker = PinyinWorker(workerRoot: workerRoot)
        usage = CandidateUsageStore(fileURL: usageFileURL, persistenceQueue: persistenceQueue)
    }

    public func recordCommittedSegments(_ segments: [CompositionState.Segment]) {
        guard !segments.isEmpty else { return }
        queue.async { [self] in
            do { try usage?.record(segments) }
            catch {
                // A disk error must never block input or disclose submitted text.
                NSLog("LocalPinyin: candidate history could not be saved; using in-memory ranking")
            }
        }
    }

    // Enqueued work retains self. Deinitialization therefore happens only after
    // the final operation has released the worker's sole owner.
    deinit { worker.stop(); try? usage?.flush() }

    public func warm() {
        guard let cancellation = warmup.begin() else { return }
        queue.async { [self] in
            defer { warmup.finish(cancellation) }
            // start cleans up a failed handshake itself. A cancelled warmup that
            // never started must not stop a healthy worker used by a newer query.
            try? worker.start(checkCancellation: cancellation.check)
        }
    }

    public func candidates(for pinyin: String, context: String = "") async throws -> [Candidate] {
        guard PinyinRules.isValid(pinyin) else { throw PinyinWorkerError.invalidInput }
        let cancellation = QueryCancellation()
        // User work takes priority over speculative startup. Duplicate warmups
        // cannot queue behind this query while it is running or awaiting the queue.
        warmup.beginQuery()
        defer { warmup.endQuery() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    do {
                        try cancellation.check()
                        let result = try worker.candidates(for: pinyin, context: context,
                                                          checkCancellation: cancellation.check)
                        try cancellation.check()
                        let ranked = usage?.ranked(result, for: pinyin) ?? result
                        try cancellation.check()
                        continuation.resume(returning: ranked)
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
        warmup.cancel()
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                worker.stop()
                do { try usage?.flush() }
                catch { NSLog("LocalPinyin: candidate history could not be flushed during shutdown") }
                continuation.resume()
            }
        }
    }

    /// Waits for all earlier learning commits and reports a persistence failure.
    /// The app's normal termination path uses this before replying to AppKit.
    public func flushLearning() async throws {
        warmup.cancel()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async { [self] in
                do { try usage?.flush(); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}

// Declare the UI-facing port separately: its main-actor requirement does not
// make this queue-owned infrastructure class or its process state main-actor bound.
extension PinyinSession: CandidateProviding {}

/// Only tokens and request counts cross threads; the worker and its descriptors
/// remain exclusively owned by PinyinSession's worker queue.
private final class WorkerWarmup: @unchecked Sendable {
    private let lock = NSLock()
    private var current: QueryCancellation?
    private var queries = 0

    func begin() -> QueryCancellation? {
        lock.lock()
        defer { lock.unlock() }
        guard current == nil, queries == 0 else { return nil }
        let cancellation = QueryCancellation()
        current = cancellation
        return cancellation
    }

    func finish(_ cancellation: QueryCancellation) {
        lock.lock()
        defer { lock.unlock() }
        if current === cancellation { current = nil }
    }

    func beginQuery() {
        lock.lock()
        defer { lock.unlock() }
        queries += 1
        current?.cancel()
    }

    func endQuery() {
        lock.lock()
        defer { lock.unlock() }
        queries -= 1
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        current?.cancel()
    }
}

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
