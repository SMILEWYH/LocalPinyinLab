import Foundation

struct Candidate: Sendable {
    let text: String
    var translation: String
    var consumedCount: Int = 0
    // Set only after Translation returns successfully; UI status labels are never spoken.
    var translationReady = false
    var speechText: String? {
        let value = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        return translationReady && needsTranslation && !value.isEmpty ? value : nil
    }
    var needsTranslation: Bool { text.range(of: "\\p{Han}", options: .regularExpression) != nil }
}

enum InputMode { case chinesePinyin, englishDirect }

struct ApplePinyinEngine: Sendable {
    let workerRoot: URL

    // 每次独立只读进程；输入及候选不写日志。
    func candidates(for pinyin: String, context: String = "") throws -> [Candidate] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-D", "WORKER_ROOT=" + workerRoot.path, "-f", workerRoot.appendingPathComponent("pinyin.sb").path,
                             workerRoot.appendingPathComponent("pinyin-worker").path, "--request"]
        // Composition/context travel only through anonymous pipes, never argv or logs.
        let input = Pipe()
        process.standardInput = input
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let request = try Self.requestData(pinyin: pinyin, context: context)
        try input.fileHandleForWriting.write(contentsOf: request)
        try input.fileHandleForWriting.close()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw EngineError.unavailable }
        return try Self.decodeCandidates(data, pinyin: pinyin)
    }
    static func requestData(pinyin: String, context: String) throws -> Data {
        try JSONEncoder().encode(Request(pinyin: pinyin, context: boundedContext(context)))
    }
    static func decodeCandidates(_ data: Data, pinyin: String) throws -> [Candidate] {
        let rows = try JSONDecoder().decode([Response].self, from: data)
        return rows.compactMap { row in
            guard let consumed = Self.consumedCount(reading: row.reading, in: pinyin) else { return nil }
            var candidate = Candidate(text: row.text, translation: "", consumedCount: consumed)
            if candidate.needsTranslation { candidate.translation = "等待本地翻译" }
            return candidate
        }
    }
    // Map the engine reading back to the original ASCII pinyin, retaining syllable separators.
    static func consumedCount(reading: String, in pinyin: String) -> Int? {
        let normalized = reading.filter { $0 != "'" }
        guard !normalized.isEmpty else { return nil }
        var matched = ""
        let letters = Array(pinyin)
        for (index, character) in letters.enumerated() {
            if character != "'" { matched.append(character) }
            guard normalized.hasPrefix(matched) else { return nil }
            if matched == normalized {
                var count = index + 1
                while count < letters.count && letters[count] == "'" { count += 1 }
                return count
            }
        }
        return nil
    }
    static func boundedContext(_ text: String) -> String {
        var result = ""
        var length = 0
        for character in text.reversed() {
            let part = String(character)
            guard length + part.utf16.count <= 128 else { break }
            result = part + result
            length += part.utf16.count
        }
        return result
    }
    private struct Request: Encodable { let pinyin: String; let context: String }
    private struct Response: Decodable { let text: String; let reading: String }
    enum EngineError: Error { case unavailable }
}
