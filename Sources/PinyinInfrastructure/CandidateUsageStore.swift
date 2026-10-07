import Darwin
import Foundation
import PinyinCore

/// Queue-owned local learning. Only committed spelling/text pairs are retained;
/// document context and incomplete compositions never enter this store.
package final class CandidateUsageStore {
    package static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LocalPinyinLab", isDirectory: true)
            .appendingPathComponent("candidate-usage.json")
    }

    private struct Key: Hashable {
        let pinyin: String
        let text: String
    }

    private struct Entry: Codable {
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
    private var entries: [Key: Entry] = [:]
    private var recency: UInt64 = 0
    private var loaded = false
    private var preserveExistingFile = false

    /// Deliberately does no filesystem work: construction may happen on the UI actor.
    package init(fileURL: URL) { self.fileURL = fileURL }

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
        // Memory remains updated if saving fails; callers may log the failure without
        // interrupting the committed text or losing learning for this process.
        // A failed read is not proof of corrupt data. Retain in-memory deltas and
        // retry loading before any write could replace the unreadable old history.
        if let readFailure { throw readFailure }
        try save()
    }

    package func ranked(_ candidates: [Candidate], for pinyin: String) -> [Candidate] {
        guard PinyinRules.isValid(pinyin) else { return candidates }
        try? loadIfNeeded()
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

    private func save() throws {
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
        guard data.count <= Self.maximumFileBytes else { throw StoreError.oversizedDocument }
        let temporary = directory.appendingPathComponent(".candidate-usage-" + UUID().uuidString + ".tmp")
        defer { try? manager.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if preserveExistingFile, manager.fileExists(atPath: fileURL.path) {
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
