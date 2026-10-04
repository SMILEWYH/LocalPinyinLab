import Foundation
import PinyinCore

/// Errors at the boundary between a validated query and the local worker.
/// No case carries composition text or document context.
public enum PinyinWorkerError: Error, Equatable, Sendable {
    case invalidInput
    case unavailable
    case timedOut
    case responseTooLarge
    case invalidResponse
}

/// Wire-format concerns stay outside the composition model and UI.
package enum WorkerProtocol {
    package static let maximumResponseBytes = 4_194_304
    package static let maximumRequestBytes = 16_384

    package static func requestData(pinyin: String, context: String) throws -> Data {
        guard PinyinRules.isValid(pinyin) else { throw PinyinWorkerError.invalidInput }
        let request = Request(pinyin: pinyin, context: PinyinRules.boundedContext(context))
        let data = try JSONEncoder().encode(request)
        guard data.count <= maximumRequestBytes else { throw PinyinWorkerError.invalidInput }
        return data
    }

    package static func decodeReady(_ data: Data) throws {
        try validateResponseSize(data)
        guard let response = try? JSONDecoder().decode(Ready.self, from: data), response.ready else {
            throw PinyinWorkerError.invalidResponse
        }
    }

    package static func decodeCandidates(_ data: Data, pinyin: String) throws -> [Candidate] {
        guard PinyinRules.isValid(pinyin) else { throw PinyinWorkerError.invalidInput }
        try validateResponseSize(data)
        guard let rows = try? JSONDecoder().decode([Response].self, from: data) else {
            throw PinyinWorkerError.invalidResponse
        }
        return rows.compactMap { row in
            guard CandidateTextPolicy.allows(row.text),
                  let consumed = PinyinRules.consumedCount(reading: row.reading, in: pinyin) else {
                return nil
            }
            return Candidate(text: row.text, consumedCount: consumed)
        }
    }

    private static func validateResponseSize(_ data: Data) throws {
        guard data.count <= maximumResponseBytes else { throw PinyinWorkerError.responseTooLarge }
    }

    /// A complete frame is bounded before it is consumed. Bytes after its LF
    /// remain buffered, so short reads and coalesced frames have identical behavior.
    package static func takeFrame(from buffer: inout Data) throws -> Data? {
        guard let end = buffer.firstIndex(of: 10) else {
            try validateResponseSize(buffer)
            return nil
        }
        let length = buffer.distance(from: buffer.startIndex, to: end)
        guard length <= maximumResponseBytes else { throw PinyinWorkerError.responseTooLarge }
        let frame = Data(buffer[..<end])
        buffer.removeSubrange(...end)
        return frame
    }

    private struct Request: Encodable { let pinyin: String; let context: String }
    private struct Response: Decodable { let text: String; let reading: String }
    private struct Ready: Decodable { let ready: Bool }
}
