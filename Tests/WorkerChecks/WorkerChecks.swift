import Darwin
import Foundation
import PinyinCore
import PinyinInfrastructure

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure(description: message) }
}

/// Copies this executable into a temporary worker bundle. The fake worker has no
/// descendants, so cancellation checks also prove that every launched PID is reaped.
private struct WorkerFixture {
    let root: URL

    init(behavior: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("localpinyin-worker-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            try FileManager.default.copyItem(at: executable, to: root.appendingPathComponent("pinyin-worker"))
            // The production profile is not changed. This fixture needs temporary
            // marker files to coordinate its simulated failures with the parent.
            try "(version 1)\n(allow default)\n".write(to: root.appendingPathComponent("pinyin.sb"), atomically: true, encoding: .utf8)
            try setBehavior(behavior)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func setBehavior(_ behavior: String) throws {
        try behavior.write(to: root.appendingPathComponent("behavior"), atomically: true, encoding: .utf8)
    }

    func lines(_ name: String) -> [String] {
        ((try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    func verifyStopped() throws {
        for line in lines("pids") {
            guard let pid = Int32(line) else { throw CheckFailure(description: "Invalid recorded PID") }
            errno = 0
            try require(kill(pid, 0) == -1 && errno == ESRCH, "Worker \(pid) is still alive after shutdown")
        }
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    @MainActor func waitForRequest(_ query: String) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !lines("requests").contains(query) {
            try require(ContinuousClock.now < deadline, "Fake worker never received \(query)")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @MainActor func waitForStart() async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while lines("pids").isEmpty {
            try require(ContinuousClock.now < deadline, "Fake worker never started")
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

@main struct WorkerChecks {
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--serve") {
            do { try runFakeWorker() } catch { exit(90) }
            return
        }
        let cases: [(String, @MainActor () async throws -> Void)] = [
            ("Cancelled query releases the queue and discards the old worker", cancelledQuery),
            ("Cancelled startup stops the handshake without retrying", cancelledHandshake),
            ("Worker exit retries once and restores a persistent connection", retryAfterExit),
            ("Response timeout still retries and recovers", retryAfterTimeout),
            ("Persistent failure stops after two attempts", retryLimit)
        ]
        var failures = 0
        for (name, run) in cases {
            do { try await run(); print("PASS: \(name)") }
            catch { failures += 1; print("FAIL: \(name) — \(error)") }
        }
        print("\(cases.count - failures)/\(cases.count) worker checks passed")
        if failures > 0 { exit(1) }
    }

    @MainActor private static func cancelledQuery() async throws {
        let fixture = try WorkerFixture(behavior: "slow-query")
        defer { fixture.remove() }
        let session = PinyinSession(workerRoot: fixture.root)
        let stale = Task { try await session.candidates(for: "n") }
        do {
            try await fixture.waitForRequest("n")
            let start = ContinuousClock.now
            stale.cancel()
            let result = try await session.candidates(for: "ni")
            let elapsed = start.duration(to: .now)
            try require(result.map(\.text) == ["你"], "The new query received an old response")
            try require(elapsed < .seconds(1.5), "New query was blocked for \(elapsed)")
            try await expectCancellation(stale)
            try require(fixture.lines("requests") == ["n", "ni"], "A cancelled query was retried")
            try require(fixture.lines("pids").count == 2, "Cancellation must replace the old worker")
            await session.shutdown()
            try fixture.verifyStopped()
            print("  latest query after cancellation: \(elapsed)")
        } catch {
            stale.cancel()
            _ = try? await stale.value
            await session.shutdown()
            throw error
        }
    }

    @MainActor private static func cancelledHandshake() async throws {
        let fixture = try WorkerFixture(behavior: "slow-handshake")
        defer { fixture.remove() }
        let session = PinyinSession(workerRoot: fixture.root)
        let stale = Task { try await session.candidates(for: "n") }
        do {
            try await fixture.waitForStart()
            let start = ContinuousClock.now
            stale.cancel()
            try await expectCancellation(stale)
            let elapsed = start.duration(to: .now)
            try require(elapsed < .seconds(1.5), "Cancelled handshake took \(elapsed)")
            try require(fixture.lines("pids").count == 1, "Cancelled startup was retried")
            try require(fixture.lines("requests").isEmpty, "Cancelled startup sent a request")
            try fixture.verifyStopped()
            try fixture.setBehavior("healthy")
            let result = try await session.candidates(for: "ni")
            try require(result.map(\.text) == ["你"], "A query after cancelled startup did not recover")
            await session.shutdown()
            try fixture.verifyStopped()
        } catch {
            stale.cancel()
            _ = try? await stale.value
            await session.shutdown()
            throw error
        }
    }

    @MainActor private static func expectCancellation(_ task: Task<[Candidate], any Error>) async throws {
        do {
            _ = try await task.value
            throw CheckFailure(description: "Cancelled query returned successfully")
        } catch is CancellationError { }
    }

    @MainActor private static func retryAfterExit() async throws { try await checkRetry(behavior: "exit-first") }
    @MainActor private static func retryAfterTimeout() async throws { try await checkRetry(behavior: "timeout-first") }

    @MainActor private static func checkRetry(behavior: String) async throws {
        let fixture = try WorkerFixture(behavior: behavior)
        defer { fixture.remove() }
        let session = PinyinSession(workerRoot: fixture.root)
        do {
            let start = ContinuousClock.now
            let first = try await session.candidates(for: "ni")
            let elapsed = start.duration(to: .now)
            try require(first.map(\.text) == ["你"], "The retry did not restore candidates")
            try require(fixture.lines("pids").count == 2, "Expected exactly one restart")
            let second = try await session.candidates(for: "hao")
            try require(second.map(\.text) == ["好"], "The restored connection returned the wrong frame")
            try require(fixture.lines("pids").count == 2, "The healthy connection was not reused")
            try require(fixture.lines("requests") == ["ni", "ni", "hao"], "Unexpected retry or frame order")
            if behavior == "timeout-first" {
                try require(elapsed >= .seconds(3) && elapsed < .seconds(5), "Response timeout changed: \(elapsed)")
            }
            await session.shutdown()
            try fixture.verifyStopped()
        } catch {
            await session.shutdown()
            throw error
        }
    }

    @MainActor private static func retryLimit() async throws {
        let fixture = try WorkerFixture(behavior: "exit-always")
        defer { fixture.remove() }
        // The synchronous diagnostic API keeps its original default arguments.
        let worker = PinyinWorker(workerRoot: fixture.root)
        defer { worker.stop() }
        do {
            _ = try worker.candidates(for: "ni")
            throw CheckFailure(description: "A permanently failed worker returned candidates")
        } catch PinyinWorkerError.unavailable { }
        worker.stop()
        try require(fixture.lines("pids").count == 2, "Permanent failure exceeded the retry limit")
        try fixture.verifyStopped()
    }

    private static func runFakeWorker() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let behavior = try String(contentsOf: root.appendingPathComponent("behavior"), encoding: .utf8)
        func append(_ text: String, to name: String) throws {
            let url = root.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) {
                _ = FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((text + "\n").utf8))
        }
        func emit(_ text: String) throws { try FileHandle.standardOutput.write(contentsOf: Data(text.utf8)) }
        func stall() -> Never {
            signal(SIGTERM, SIG_IGN)
            while true { pause() }
        }
        let previousStarts = ((try? String(contentsOf: root.appendingPathComponent("pids"), encoding: .utf8)) ?? "")
            .split(separator: "\n").count
        try append(String(getpid()), to: "pids")
        if behavior == "slow-handshake" { stall() }
        try emit("{\"ready\":true}\n")
        var buffer = Data()
        while true {
            let chunk = FileHandle.standardInput.availableData
            if chunk.isEmpty { return }
            buffer.append(chunk)
            while let end = buffer.firstIndex(of: 10) {
                let frame = Data(buffer[..<end])
                buffer.removeSubrange(...end)
                guard let request = try JSONSerialization.jsonObject(with: frame) as? [String: String],
                      let query = request["pinyin"] else { exit(91) }
                try append(query, to: "requests")
                if behavior == "exit-always" || (behavior == "exit-first" && previousStarts == 0) { exit(21) }
                if behavior == "slow-query" && query == "n" {
                    // Leave an unfinished old frame behind; the next query must
                    // never inherit it when cancellation replaces this worker.
                    try emit("[{\"text\":\"旧\",\"reading\":\"n\"")
                    stall()
                }
                if behavior == "timeout-first" && previousStarts == 0 { stall() }
                let text = query == "ni" ? "你" : "好"
                try emit("[{\"text\":\"\(text)\",\"reading\":\"\(query)\"}]\n")
            }
        }
    }
}
