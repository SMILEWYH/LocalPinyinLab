import Foundation
import PinyinCore
import PinyinInfrastructure

private struct UsageCheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func requireUsage(_ condition: Bool, _ message: String) throws {
    if !condition { throw UsageCheckFailure(description: message) }
}

private struct UsageFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("localpinyin-usage-check-" + UUID().uuidString)
    var file: URL { root.appendingPathComponent("learning/candidate-usage.json") }

    func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private final class UsageWriteGate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var attempts = 0
    private let failFirst: Bool

    init(failFirst: Bool) { self.failFirst = failFirst }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return attempts
    }

    func beforeWrite() throws {
        lock.lock()
        attempts += 1
        let first = attempts == 1
        lock.unlock()
        if first {
            entered.signal()
            release.wait()
            if failFirst { throw UsageCheckFailure(description: "Injected first write failure") }
        }
    }
}

enum CandidateUsageChecks {
    static var cases: [(String, @Sendable () throws -> Void)] {
        [
            ("Learned candidates use frequency, recency and stable engine order", ranking),
            ("Learning loads lazily and persists privately across restarts", persistence),
            ("Learning preserves the engine's consumption-length positions", consumptionLengths),
            ("Learning preserves internal apostrophe distinctions", spellings),
            ("Learning ignores raw pinyin and malformed candidate text", invalidSelections),
            ("Broken learning files fall back and retain their original bytes", brokenFiles),
            ("Temporary read failures preserve and merge existing learning", retryReadFailure),
            ("Learning remains usable when a save fails", failedSave),
            ("Pending learning snapshots keep memory current and flush the latest state", deferredSnapshots),
            ("Commits during an in-flight write survive both success and failure", inFlightSnapshots),
            ("A failed asynchronous write can flush after recovery without another commit", retryFlush),
            ("A failed snapshot retries in the background without another commit", automaticRetry),
            ("Learning bounds loaded records and handles sequence overflow", storageBounds)
        ]
    }

    private static func segments(_ text: String, _ pinyin: String) throws -> [CompositionState.Segment] {
        var state = CompositionState()
        try requireUsage(state.append(pinyin), "Invalid fixture pinyin: \(pinyin)")
        try requireUsage(state.choose(Candidate(text: text, consumedCount: pinyin.count)), "Invalid fixture candidate")
        return state.segments
    }

    private static func record(_ text: String, _ pinyin: String, in store: CandidateUsageStore) throws {
        try store.record(segments(text, pinyin))
        try store.flush()
    }

    private static func candidates(_ texts: [String], length: Int) -> [Candidate] {
        texts.map { Candidate(text: $0, consumedCount: length) }
    }

    private static func ranking() throws {
        let fixture = UsageFixture()
        defer { fixture.remove() }
        let store = CandidateUsageStore(fileURL: fixture.file)
        let original = candidates(["你", "尼", "泥", "妮"], length: 2)
        try requireUsage(store.ranked(original, for: "ni") == original, "Unlearned order changed")
        try record("尼", "ni", in: store)
        try record("泥", "ni", in: store)
        try requireUsage(store.ranked(original, for: "ni").map(\.text) == ["泥", "尼", "你", "妮"], "Recent equal-frequency choice did not lead")
        try record("尼", "ni", in: store)
        try record("妮", "ni", in: store)
        try requireUsage(store.ranked(original, for: "ni").map(\.text) == ["尼", "妮", "泥", "你"], "Frequency did not take precedence over recency")
        let absent = candidates(["你", "妮"], length: 2)
        try requireUsage(store.ranked(absent, for: "ni").map(\.text) == ["妮", "你"], "Learning injected a candidate absent from the engine response")
    }

    private static func persistence() throws {
        let fixture = UsageFixture()
        defer { fixture.remove() }
        let store = CandidateUsageStore(fileURL: fixture.file)
        try requireUsage(!FileManager.default.fileExists(atPath: fixture.root.path), "Initialization performed filesystem writes")
        try record("泥", "ni", in: store)
        let restarted = CandidateUsageStore(fileURL: fixture.file)
        let original = candidates(["你", "泥"], length: 2)
        try requireUsage(restarted.ranked(original, for: "ni").first?.text == "泥", "Learning was lost on restart")
        let fileMode = try FileManager.default.attributesOfItem(atPath: fixture.file.path)[.posixPermissions] as? NSNumber
        let directoryMode = try FileManager.default.attributesOfItem(atPath: fixture.file.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
        try requireUsage(fileMode?.intValue == 0o600 && directoryMode?.intValue == 0o700, "Learning data permissions are not private")
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.file)) as? [String: Any]
        let entries = document?["entries"] as? [[String: Any]]
        try requireUsage(Set(document?.keys.map { $0 } ?? []) == ["version", "entries"], "Unexpected document fields")
        try requireUsage(Set(entries?.first?.keys.map { $0 } ?? []) == ["pinyin", "text", "count", "recency"], "Learning retained data beyond the selected spelling/text counters")

        // The initializer must also defer reads until the queue first uses the store.
        let deferredFile = fixture.root.appendingPathComponent("deferred/candidate-usage.json")
        let deferred = CandidateUsageStore(fileURL: deferredFile)
        try FileManager.default.createDirectory(at: deferredFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.file, to: deferredFile)
        try requireUsage(deferred.ranked(original, for: "ni").first?.text == "泥", "Initialization eagerly read the absent file")
    }

    private static func consumptionLengths() throws {
        let fixture = UsageFixture()
        defer { fixture.remove() }
        let store = CandidateUsageStore(fileURL: fixture.file)
        try record("你", "ni", in: store)
        let original = [
            Candidate(text: "你好", consumedCount: 5),
            Candidate(text: "尼", consumedCount: 2),
            Candidate(text: "拟好", consumedCount: 5),
            Candidate(text: "你", consumedCount: 2),
            Candidate(text: "泥", consumedCount: 2)
        ]
        let ranked = store.ranked(original, for: "nihao")
        try requireUsage(ranked.map(\.text) == ["你好", "你", "拟好", "尼", "泥"], "A shorter choice displaced a longer phrase or changed unmatched order")
        try requireUsage(zip(ranked, original).allSatisfy { $0.consumedCount == $1.consumedCount }, "Consumption slots changed")
        let invalidLengths = [Candidate(text: "你", consumedCount: 0), Candidate(text: "尼", consumedCount: 20)]
        try requireUsage(store.ranked(invalidLengths, for: "ni") == invalidLengths, "Malformed consumption lengths changed")
    }

    private static func spellings() throws {
        let fixture = UsageFixture()
        defer { fixture.remove() }
        let store = CandidateUsageStore(fileURL: fixture.file)
        try record("西安", "'xi'an'", in: store)
        let separate = candidates(["先", "西安"], length: 5)
        try requireUsage(store.ranked(separate, for: "xi'an").first?.text == "西安", "Boundary apostrophes were not normalized")
        let joined = candidates(["先", "西安"], length: 4)
        try requireUsage(store.ranked(joined, for: "xian") == joined, "Internal apostrophes were discarded")
        let trailing = candidates(["先", "西安"], length: 6)
        try requireUsage(store.ranked(trailing, for: "xi'an'").first?.text == "西安", "Trailing consumed separator prevented learning lookup")
        try record("你", "ni", in: store)
        try requireUsage(store.ranked(candidates(["尼", "你"], length: 2), for: "na").first?.text == "尼", "Learning leaked across spellings")
    }

    private static func invalidSelections() throws {
        let fixture = UsageFixture()
        defer { fixture.remove() }
        let store = CandidateUsageStore(fileURL: fixture.file)
        for (text, spelling) in [("ni", "ni"), ("ASCII", "ni"), ("...", "ni"), ("你\n", "ni"),
                                 (String(repeating: "你", count: 200), "ni"), ("你", "'''")] {
            try record(text, spelling, in: store)
        }
        try store.record([])
        try requireUsage(!FileManager.default.fileExists(atPath: fixture.file.path), "Invalid selections were saved")
        try record("你", "ni", in: store)
        let original = candidates(["尼", "你"], length: 2)
        try requireUsage(store.ranked(original, for: "NI") == original, "Invalid query was normalized into another key")
        try requireUsage(store.ranked(original, for: "ni").first?.text == "你", "Rejected entries disabled later valid learning")
    }

    private static func brokenFiles() throws {
        let payloads = [
            Data("{broken json".utf8),
            try JSONSerialization.data(withJSONObject: ["version": 99, "entries": []]),
            try JSONSerialization.data(withJSONObject: ["version": 1, "entries": [
                ["pinyin": "ni", "text": "你😀", "count": 99, "recency": 1]
            ]]),
            try JSONSerialization.data(withJSONObject: ["version": 1, "entries": [
                ["pinyin": "ni", "text": "你", "count": 0, "recency": 1]
            ]])
        ]
        for payload in payloads {
            let fixture = UsageFixture()
            defer { fixture.remove() }
            try fixture.prepareDirectory()
            try payload.write(to: fixture.file)
            let store = CandidateUsageStore(fileURL: fixture.file)
            let original = candidates(["尼", "你"], length: 2)
            try requireUsage(store.ranked(original, for: "ni") == original, "Corrupt file changed engine fallback order")
            try requireUsage(try Data(contentsOf: fixture.file) == payload, "Reading corrupt data changed its original bytes")
            try record("你", "ni", in: store)
            let files = try FileManager.default.contentsOfDirectory(at: fixture.file.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            let backup = files.filter { $0.lastPathComponent.contains(".corrupt-") }
            try requireUsage(backup.count == 1, "Corrupt learning file was not retained before recovery")
            try requireUsage(try Data(contentsOf: backup[0]) == payload, "Corrupt backup bytes were changed")
            try store.record(segments("你", "ni"))
            try store.record(segments("你", "ni"))
            try store.flush()
            try store.flush()
            let afterFlush = try FileManager.default.contentsOfDirectory(at: fixture.file.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            try requireUsage(afterFlush.filter { $0.lastPathComponent.contains(".corrupt-") }.count == 1,
                             "Later snapshots or repeated flushes backed up a healthy replacement")
            try requireUsage(try Data(contentsOf: backup[0]) == payload, "Later snapshots changed the corrupt backup")
            let restarted = CandidateUsageStore(fileURL: fixture.file)
            try requireUsage(restarted.ranked(original, for: "ni").first?.text == "你", "Learning did not recover after corruption")
        }
    }

    private static func failedSave() throws {
        let fixture = UsageFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        // A regular file in place of the parent directory fails even for privileged tests.
        let blocker = fixture.file.deletingLastPathComponent()
        try Data("block writes".utf8).write(to: blocker)
        let store = CandidateUsageStore(fileURL: fixture.file)
        var saveFailed = false
        do { try record("泥", "ni", in: store) } catch { saveFailed = true }
        try requireUsage(saveFailed, "An impossible save unexpectedly succeeded")
        let original = candidates(["你", "泥"], length: 2)
        try requireUsage(store.ranked(original, for: "ni").first?.text == "泥", "Failed persistence discarded in-memory learning")
        try FileManager.default.removeItem(at: blocker)
        try record("泥", "ni", in: store)
        try requireUsage(CandidateUsageStore(fileURL: fixture.file).ranked(original, for: "ni").first?.text == "泥", "A later save did not recover")
    }

    private static func retryReadFailure() throws {
        let fixture = UsageFixture()
        defer { fixture.remove() }
        let initial = CandidateUsageStore(fileURL: fixture.file)
        for text in ["你", "你", "你", "泥", "妮"] { try record(text, "ni", in: initial) }
        let oldData = try Data(contentsOf: fixture.file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fixture.file.path)
        let recovering = CandidateUsageStore(fileURL: fixture.file)
        let original = candidates(["你", "泥", "妮", "尼"], length: 2)
        try requireUsage(recovering.ranked(original, for: "ni") == original, "An unreadable store changed fallback order")
        for text in ["你", "泥", "尼"] {
            var failed = false
            do { try record(text, "ni", in: recovering) } catch { failed = true }
            try requireUsage(failed, "Reading a mode-000 file must fail and prevent a destructive save")
        }
        try requireUsage(recovering.ranked(original, for: "ni").map(\.text) == ["尼", "泥", "你", "妮"], "Temporary read errors discarded in-memory learning")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.file.path)
        try requireUsage(try Data(contentsOf: fixture.file) == oldData, "A failed read replaced the original history")
        // Retry through the read path first, then commit one more selection. The
        // in-memory deltas must merge only once and retain their relative recency.
        try requireUsage(recovering.ranked(original, for: "ni").map(\.text) == ["你", "泥", "尼", "妮"], "Restored history did not merge with recent in-memory selections")
        try record("妮", "ni", in: recovering)
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.file)) as? [String: Any]
        let saved = document?["entries"] as? [[String: Any]] ?? []
        let counts = Dictionary(uniqueKeysWithValues: saved.compactMap { entry -> (String, Int)? in
            guard let text = entry["text"] as? String, let count = entry["count"] as? Int else { return nil }
            return (text, count)
        })
        try requireUsage(counts == ["你": 4, "泥": 2, "妮": 2, "尼": 1], "Recovery lost old counts or double-counted pending learning")
        let restarted = CandidateUsageStore(fileURL: fixture.file)
        try requireUsage(restarted.ranked(original, for: "ni").map(\.text) == ["你", "妮", "泥", "尼"], "Merged counts or recency were not persisted")
        let files = try FileManager.default.contentsOfDirectory(at: fixture.file.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        try requireUsage(!files.contains { $0.lastPathComponent.contains(".corrupt-") }, "An I/O failure incorrectly classified valid history as corrupt")
    }

    private static func deferredSnapshots() throws {
        let fixture = UsageFixture()
        defer { fixture.remove() }
        let queue = DispatchQueue(label: "localpinyin-check.deferred-save")
        queue.suspend()
        let store = CandidateUsageStore(fileURL: fixture.file, persistenceQueue: queue)
        do {
            for _ in 0..<20 { try store.record(segments("泥", "ni")) }
            try store.record(segments("尼", "ni"))
            try requireUsage(store.ranked(candidates(["你", "尼", "泥"], length: 2), for: "ni").first?.text == "泥",
                             "Pending writes blocked immediate in-memory ranking")
            try requireUsage(!FileManager.default.fileExists(atPath: fixture.file.path), "Recording performed a write outside the persistence queue")
        } catch {
            queue.resume()
            try? store.flush()
            throw error
        }
        queue.resume()
        try store.flush()
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.file)) as? [String: Any]
        let entries = document?["entries"] as? [[String: Any]] ?? []
        try requireUsage(entries.count == 2 && entries.first { $0["text"] as? String == "泥" }?["count"] as? Int == 20,
                         "An older pending snapshot overwrote the latest learning")
        let restart = CandidateUsageStore(fileURL: fixture.file)
        try requireUsage(restart.ranked(candidates(["你", "尼", "泥"], length: 2), for: "ni").first?.text == "泥",
                         "Explicit flush did not make the latest ranking durable")
    }

    private static func retryFlush() throws {
        let fixture = UsageFixture()
        defer { fixture.remove() }
        let store = CandidateUsageStore(fileURL: fixture.file)
        // Establish an empty, readable store before introducing a write failure.
        _ = store.ranked(candidates(["你", "泥"], length: 2), for: "ni")
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        let blocker = fixture.file.deletingLastPathComponent()
        try Data("block writes".utf8).write(to: blocker)
        try store.record(segments("泥", "ni"))
        var failed = false
        do { try store.flush() } catch { failed = true }
        try requireUsage(failed, "Flush failed to report an impossible asynchronous save")
        try store.record(segments("泥", "ni"))
        try store.record(segments("尼", "ni"))
        try FileManager.default.removeItem(at: blocker)
        try store.flush()
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.file)) as? [String: Any]
        let entries = document?["entries"] as? [[String: Any]] ?? []
        try requireUsage(entries.count == 2 && entries.first { $0["text"] as? String == "泥" }?["count"] as? Int == 2,
                         "Recovering a failed write lost or replayed committed counts")
        // A second flush without a new commit must preserve the saved bytes.
        let saved = try Data(contentsOf: fixture.file)
        try store.flush()
        try requireUsage(try Data(contentsOf: fixture.file) == saved, "An obsolete scheduled save replaced the flushed snapshot")
    }

    private static func inFlightSnapshots() throws {
        for failFirst in [false, true] {
            let fixture = UsageFixture()
            defer { fixture.remove() }
            let gate = UsageWriteGate(failFirst: failFirst)
            defer { gate.release.signal() }
            let store = CandidateUsageStore(fileURL: fixture.file, beforePersistence: gate.beforeWrite)
            try store.record(segments("泥", "ni"))
            try requireUsage(gate.entered.wait(timeout: .now() + 3) == .success, "The first write never reached its gate")
            // The persistence queue is now inside the first write. New submissions
            // must replace the mailbox snapshot without waiting for that queue.
            for _ in 0..<19 { try store.record(segments("泥", "ni")) }
            try store.record(segments("尼", "ni"))
            gate.release.signal()
            try store.flush()
            let document = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.file)) as? [String: Any]
            let entries = document?["entries"] as? [[String: Any]] ?? []
            try requireUsage(entries.count == 2 && entries.first { $0["text"] as? String == "泥" }?["count"] as? Int == 20,
                             "Finishing an older in-flight snapshot lost newer learning")
            try requireUsage(gate.count == 2, "Queued commits were not coalesced into one latest snapshot")
        }
    }

    private static func automaticRetry() throws {
        let fixture = UsageFixture()
        defer { fixture.remove() }
        let store = CandidateUsageStore(fileURL: fixture.file)
        _ = store.ranked(candidates(["你", "泥"], length: 2), for: "ni")
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        let blocker = fixture.file.deletingLastPathComponent()
        try Data("block writes".utf8).write(to: blocker)
        try store.record(segments("泥", "ni"))
        var failed = false
        do { try store.flush() } catch { failed = true }
        try requireUsage(failed, "The retry fixture did not produce a write failure")
        try FileManager.default.removeItem(at: blocker)
        let deadline = ContinuousClock.now + .seconds(3)
        while !FileManager.default.fileExists(atPath: fixture.file.path), ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        try requireUsage(FileManager.default.fileExists(atPath: fixture.file.path), "Pending learning was not retried after filesystem recovery")
        let restart = CandidateUsageStore(fileURL: fixture.file)
        try requireUsage(restart.ranked(candidates(["你", "泥"], length: 2), for: "ni").first?.text == "泥",
                         "Background retry did not preserve the original snapshot")
        try store.flush()
    }

    private static func storageBounds() throws {
        let fixture = UsageFixture()
        defer { fixture.remove() }
        try fixture.prepareDirectory()
        let initial: [[String: Any]] = (1...10_000).map { index in
            ["pinyin": "ni", "text": "你\(index)", "count": 1, "recency": index]
        }
        try JSONSerialization.data(withJSONObject: ["version": 1, "entries": initial]).write(to: fixture.file)
        let store = CandidateUsageStore(fileURL: fixture.file)
        try record("泥", "ni", in: store)
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.file)) as? [String: Any]
        let saved = document?["entries"] as? [[String: Any]] ?? []
        try requireUsage(saved.count == 10_000, "Record count exceeded its storage bound")
        try requireUsage(!saved.contains { $0["text"] as? String == "你1" }, "Least-recent entry was not evicted")
        try requireUsage(saved.contains { $0["text"] as? String == "泥" }, "New entry was evicted instead of old data")

        // A loaded sequence can reach the numeric limit; recording must not trap.
        try Data("{\"version\":1,\"entries\":[{\"pinyin\":\"ni\",\"text\":\"你\",\"count\":1000000,\"recency\":18446744073709551615}]}".utf8).write(to: fixture.file)
        let overflow = CandidateUsageStore(fileURL: fixture.file)
        try record("你", "ni", in: overflow)
        try requireUsage(overflow.ranked(candidates(["尼", "你"], length: 2), for: "ni").first?.text == "你", "Counter overflow broke learned ranking")
    }
}
