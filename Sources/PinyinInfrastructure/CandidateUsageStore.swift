import Darwin
import Foundation
import PinyinCore

/// Queue-owned local learning. Only committed spelling/text pairs are retained;
/// document context and incomplete compositions never enter this store.
/// The owner flushes at shutdown; releasing a standalone store is not a flush.
package final class CandidateUsageStore {
    package static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LocalPinyinLab", isDirectory: true)
            .appendingPathComponent("candidate-usage.json")
    }

    private struct Key: Hashable, Sendable {
        let pinyin: String
        let text: String
    }

    private struct Entry: Codable, Sendable {
        let pinyin: String
        let text: String
        var count: UInt64
        var recency: UInt64
        var key: Key { Key(pinyin: pinyin, text: text) }
    }

    private struct Document: Codable {
        let version: Int
        let entries: [Entry]
    }

    private enum StoreError: Error { case invalidDocument, invalidFileType, oversizedDocument }
    private static let maximumEntries = 10_000
    private static let maximumFileBytes = 8 * 1_024 * 1_024
    private static let maximumCount: UInt64 = 1_000_000
    private let fileURL: URL
    private let persistence: Persistence
    private var entries: [Key: Entry] = [:]
    private var recency: UInt64 = 0
    private var loaded = false
    private var preserveExistingFile = false
    private var needsScheduling = false

    /// Deliberately does no filesystem work: construction may happen on the UI actor.
    package init(fileURL: URL, persistenceQueue: DispatchQueue? = nil,
                 beforePersistence: (@Sendable () throws -> Void)? = nil) {
        self.fileURL = fileURL
        persistence = Persistence(fileURL: fileURL, queue: persistenceQueue, beforePersistence: beforePersistence)
    }

    package func record(_ segments: [CompositionState.Segment]) throws {
        var readFailure: (any Error)?
        do { try loadIfNeeded() } catch { readFailure = error }
        var changed = false
        // A composition contains at most 128 input characters and selected segments.
        for segment in segments.prefix(PinyinRules.maxInputLength) {
            guard let pinyin = Self.normalized(segment.pinyin), Self.isLearnable(segment.text) else { continue }
            advanceRecency()
            let key = Key(pinyin: pinyin, text: segment.text)
            var entry = entries[key] ?? Entry(pinyin: pinyin, text: segment.text, count: 0, recency: 0)
            entry.count = min(entry.count + 1, Self.maximumCount)
            entry.recency = recency
            entries[key] = entry
            changed = true
        }
        guard changed else { return }
        trimEntries()
        needsScheduling = true
        // Memory remains updated if saving fails; callers may log the failure without
        // interrupting the committed text or losing learning for this process.
        // A failed read is not proof of corrupt data. Retain in-memory deltas and
        // retry loading before any write could replace the unreadable old history.
        if let readFailure { throw readFailure }
        scheduleIfNeeded()
    }

    /// Call on the store's owning queue. Used at explicit durability boundaries,
    /// never for ordinary candidate queries or commits.
    package func flush() throws {
        if needsScheduling {
            try loadIfNeeded()
            scheduleIfNeeded()
        }
        try persistence.flush()
    }

    private func scheduleIfNeeded() {
        guard loaded, needsScheduling else { return }
        // Dictionary value semantics give the writer an immutable snapshot;
        // sorting, encoding and filesystem work all happen on its own queue.
        persistence.submit(entries, preserveExistingFile: preserveExistingFile)
        needsScheduling = false
    }

    package func ranked(_ candidates: [Candidate], for pinyin: String) -> [Candidate] {
        guard PinyinRules.isValid(pinyin) else { return candidates }
        try? loadIfNeeded()
        scheduleIfNeeded()
        guard !entries.isEmpty else { return candidates }
        var result = candidates
        let groups = Dictionary(grouping: candidates.indices) { candidates[$0].consumedCount }
        for (consumedCount, slots) in groups {
            guard consumedCount > 0, consumedCount <= pinyin.count,
                  let spelling = Self.normalized(String(pinyin.prefix(consumedCount))) else { continue }
            let ordered = slots.sorted { lhs, rhs in
                let left = entries[Key(pinyin: spelling, text: candidates[lhs].text)]
                let right = entries[Key(pinyin: spelling, text: candidates[rhs].text)]
                if (left?.count ?? 0) != (right?.count ?? 0) { return (left?.count ?? 0) > (right?.count ?? 0) }
                if (left?.recency ?? 0) != (right?.recency ?? 0) { return (left?.recency ?? 0) > (right?.recency ?? 0) }
                return lhs < rhs
            }
            // Preserve the engine's positions for other consumption lengths, so a
            // frequently selected short character cannot displace a complete phrase.
            for (slot, source) in zip(slots, ordered) { result[slot] = candidates[source] }
        }
        return result
    }

    private static func normalized(_ pinyin: String) -> String? {
        guard PinyinRules.isValid(pinyin) else { return nil }
        let value = pinyin.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        return value.isEmpty ? nil : value
    }

    private static func isLearnable(_ text: String) -> Bool {
        guard !text.isEmpty, text.utf8.count <= 512, text.count <= PinyinRules.maxInputLength,
              CandidateTextPolicy.allows(text), text == text.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        return text.range(of: "\\p{Han}", options: .regularExpression) != nil
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        let attributes: [FileAttributeKey: Any]
        do {
            // fileExists also returns false for permission errors; only a confirmed
            // missing file is safe to treat as a fresh learning store.
            attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        } catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain,
               failure.code == CocoaError.fileNoSuchFile.rawValue || failure.code == CocoaError.fileReadNoSuchFile.rawValue {
                loaded = true
                return
            }
            throw error
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw StoreError.invalidFileType }
        guard let size = attributes[.size] as? NSNumber else { throw StoreError.invalidDocument }
        if size.uint64Value > UInt64(Self.maximumFileBytes) {
            loaded = true
            preserveExistingFile = true
            return
        }
        // Opening and reading remain outside the content-validation catch. Their
        // errors are retryable and never authorize moving or overwriting old data.
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumFileBytes + 1) ?? Data()
        let validated: [Key: Entry]
        do {
            guard data.count <= Self.maximumFileBytes else { throw StoreError.oversizedDocument }
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.version == 1, document.entries.count <= Self.maximumEntries else { throw StoreError.invalidDocument }
            var records: [Key: Entry] = [:]
            for entry in document.entries {
                guard Self.normalized(entry.pinyin) == entry.pinyin, Self.isLearnable(entry.text),
                      entry.count > 0, entry.count <= Self.maximumCount, entry.recency > 0,
                      records[entry.key] == nil else { throw StoreError.invalidDocument }
                records[entry.key] = entry
            }
            validated = records
        } catch {
            // Do not rename or overwrite a broken file merely because someone typed.
            // If a later commit saves new learning, preserve its exact original bytes.
            loaded = true
            preserveExistingFile = true
            return
        }
        let pending = entries.values.sorted { $0.recency < $1.recency }
        entries = validated
        recency = validated.values.map(\.recency).max() ?? 0
        for delta in pending {
            advanceRecency()
            var combined = entries[delta.key] ?? Entry(pinyin: delta.pinyin, text: delta.text, count: 0, recency: 0)
            combined.count = min(combined.count + delta.count, Self.maximumCount)
            combined.recency = recency
            entries[delta.key] = combined
        }
        trimEntries()
        loaded = true
    }

    private func trimEntries() {
        guard entries.count > Self.maximumEntries else { return }
        let retained = entries.values.sorted { $0.recency > $1.recency }.prefix(Self.maximumEntries)
        entries = Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0) })
    }

    private func advanceRecency() {
        if recency == UInt64.max {
            let ordered = entries.values.sorted { lhs, rhs in
                if lhs.recency != rhs.recency { return lhs.recency < rhs.recency }
                if lhs.pinyin != rhs.pinyin { return lhs.pinyin < rhs.pinyin }
                return lhs.text < rhs.text
            }
            for (index, var entry) in ordered.enumerated() {
                entry.recency = UInt64(index + 1)
                entries[entry.key] = entry
            }
            recency = UInt64(entries.count)
        }
        recency += 1
    }

    /// A locked mailbox retains only the latest waiting snapshot, even while a
    /// slow write occupies the serial queue. All filesystem state is queue-owned.
    private final class Persistence: @unchecked Sendable {
        private struct Snapshot: Sendable {
            let id = UUID()
            let entries: [Key: Entry]
            let preserveExistingFile: Bool
        }
        private let fileURL: URL
        private let queue: DispatchQueue
        // Deterministic fault/ordering checks can pause an in-flight write here.
        private let beforePersistence: (@Sendable () throws -> Void)?
        private let lock = NSLock()
        private var pending: Snapshot?
        private var drainEnqueued = false
        private var preserveExistingFile: Bool?
        private var scheduled: DispatchWorkItem?
        private var failures = 0
        private var lastAttemptID: UUID?

        init(fileURL: URL, queue: DispatchQueue?, beforePersistence: (@Sendable () throws -> Void)?) {
            self.fileURL = fileURL
            self.queue = queue ?? DispatchQueue(label: "local.pinyinlab.learning", qos: .utility)
            self.beforePersistence = beforePersistence
        }

        func submit(_ entries: [Key: Entry], preserveExistingFile: Bool) {
            lock.lock()
            pending = Snapshot(entries: entries, preserveExistingFile: preserveExistingFile)
            let enqueue = !drainEnqueued
            drainEnqueued = true
            lock.unlock()
            guard enqueue else { return }
            queue.async { [self] in
                if scheduled == nil { schedule(after: .milliseconds(100)) }
            }
        }

        func flush() throws {
            try queue.sync {
                scheduled?.cancel()
                scheduled = nil
                do { try savePending() }
                catch { retryAfterFailure(); throw error }
            }
        }

        private func schedule(after delay: DispatchTimeInterval) {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.scheduled = nil
                do { try self.savePending() }
                catch {
                    if self.failures == 0 {
                        NSLog("LocalPinyin: candidate history could not be saved; retaining pending learning")
                    }
                    self.retryAfterFailure()
                }
            }
            scheduled = work
            queue.asyncAfter(deadline: .now() + delay, execute: work)
        }

        private func retryAfterFailure() {
            lock.lock()
            let superseded = pending?.id != lastAttemptID
            if superseded { failures = 0 }
            failures += 1
            // Bound background retries. The next commit or explicit flush still
            // retries the retained snapshot after the filesystem recovers.
            if failures > 3 { drainEnqueued = false }
            lock.unlock()
            if failures <= 3 {
                schedule(after: superseded ? .milliseconds(100) : .seconds(1 << (failures - 1)))
            }
        }

        private func savePending() throws {
            lock.lock()
            let snapshot = pending
            pending = nil
            if snapshot == nil { drainEnqueued = false }
            lock.unlock()
            guard let snapshot else { return }
            if lastAttemptID != snapshot.id { failures = 0 }
            lastAttemptID = snapshot.id
            // Only the initial file needs preservation. Later snapshots must
            // never classify a successfully saved replacement as corrupt.
            if preserveExistingFile == nil { preserveExistingFile = snapshot.preserveExistingFile }
            do {
                try beforePersistence?()
                try save(snapshot.entries)
            }
            catch {
                lock.lock()
                // A commit made during this write takes precedence over its
                // failed predecessor. Never restore an obsolete snapshot over it.
                if pending == nil { pending = snapshot }
                lock.unlock()
                throw error
            }
            failures = 0
            lock.lock()
            let hasNewer = pending != nil
            if !hasNewer { drainEnqueued = false }
            lock.unlock()
            if hasNewer { schedule(after: .milliseconds(100)) }
        }

        private func save(_ entries: [Key: Entry]) throws {
            let manager = FileManager.default
            let directory = fileURL.deletingLastPathComponent()
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            guard try manager.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else {
                throw StoreError.invalidFileType
            }
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            if manager.fileExists(atPath: fileURL.path) {
                guard try manager.attributesOfItem(atPath: fileURL.path)[.type] as? FileAttributeType == .typeRegular else {
                    throw StoreError.invalidFileType
                }
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(Document(version: 1, entries: entries.values.sorted { $0.recency < $1.recency }))
            guard data.count <= CandidateUsageStore.maximumFileBytes else { throw StoreError.oversizedDocument }
            let temporary = directory.appendingPathComponent(".candidate-usage-" + UUID().uuidString + ".tmp")
            defer { try? manager.removeItem(at: temporary) }
            try data.write(to: temporary, options: .withoutOverwriting)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            if preserveExistingFile == true, manager.fileExists(atPath: fileURL.path) {
                let backup = directory.appendingPathComponent(fileURL.lastPathComponent + ".corrupt-" + UUID().uuidString)
                try manager.moveItem(at: fileURL, to: backup)
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
            }
            guard rename(temporary.path, fileURL.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            preserveExistingFile = false
        }
    }
}
