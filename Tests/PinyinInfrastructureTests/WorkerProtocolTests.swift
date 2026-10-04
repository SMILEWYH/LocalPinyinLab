import Foundation
import TestSupport
import PinyinCore
import PinyinInfrastructure

@main
struct WorkerProtocolTests {
    static func main() throws {
        let tests = WorkerProtocolTests()
        try tests.testInvalidInputIsRejectedBeforeStartingAWorker()
        try tests.testRequestPreservesPinyinAndBoundsContextByWholeCharacters()
        try tests.testCandidatesPreserveOrderDuplicatesEmojiAndRawPrefixLengths()
        try tests.testUnmappableAndEmptyCandidatesAreFiltered()
        try tests.testMalformedResponseAndReadinessHaveExplicitErrors()
        try tests.testResponseSizeLimitIncludesTheFinalPayloadByte()
        try tests.testPartialAndCoalescedFramesDoNotLoseBytes()
        print("PASS: worker validation, wire codec, candidate mapping and bounded frame protocol")
    }

    func testInvalidInputIsRejectedBeforeStartingAWorker() throws {
        let worker = PinyinWorker(workerRoot: URL(fileURLWithPath: "/nonexistent-worker"))
        for pinyin in ["", "N", "你好", "invalid!", String(repeating: "a", count: 129)] {
            XCTAssertThrowsError(try worker.candidates(for: pinyin)) { error in
                XCTAssertEqual(error as? PinyinWorkerError, .invalidInput)
            }
            XCTAssertNil(worker.processIdentifier)
        }
    }

    func testRequestPreservesPinyinAndBoundsContextByWholeCharacters() throws {
        let context = String(repeating: "中文👨‍👩‍👧‍👦e\u{301}", count: 50)
        let data = try WorkerProtocol.requestData(pinyin: "xi'an", context: context)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(decoded["pinyin"], "xi'an")
        let bounded = try XCTUnwrap(decoded["context"])
        XCTAssertLessThanOrEqual(bounded.utf16.count, 128)
        XCTAssertTrue(context.hasSuffix(bounded))
        XCTAssertEqual(bounded.last, context.last)
        XCTAssertLessThanOrEqual(data.count, WorkerProtocol.maximumRequestBytes)
        XCTAssertFalse(data.contains(10), "The transport adds the single newline frame terminator")
    }

    func testCandidatesPreserveOrderDuplicatesEmojiAndRawPrefixLengths() throws {
        let data = Data(#"[{"text":"西","reading":"xi"},{"text":"👋","reading":"xi'an"},{"text":"西","reading":"xi"}]"#.utf8)
        let candidates = try WorkerProtocol.decodeCandidates(data, pinyin: "xi'an")
        XCTAssertEqual(candidates.map(\.text), ["西", "👋", "西"])
        XCTAssertEqual(candidates.map(\.consumedCount), [3, 5, 3])
    }

    func testUnmappableAndEmptyCandidatesAreFiltered() throws {
        let data = Data(#"[{"text":"","reading":"ni"},{"text":"好","reading":"hao"},{"text":"你","reading":""},{"text":"你好","reading":"ni'hao"}]"#.utf8)
        let candidates = try WorkerProtocol.decodeCandidates(data, pinyin: "nihao")
        XCTAssertEqual(candidates.map(\.text), ["你好"])
        XCTAssertEqual(candidates.map(\.consumedCount), [5])
    }

    func testMalformedResponseAndReadinessHaveExplicitErrors() throws {
        for json in ["not json", #"{"text":"你好"}"#, #"[{"text":"你好"}]"#] {
            XCTAssertThrowsError(try WorkerProtocol.decodeCandidates(Data(json.utf8), pinyin: "nihao")) { error in
                XCTAssertEqual(error as? PinyinWorkerError, .invalidResponse)
            }
        }
        XCTAssertNoThrow(try WorkerProtocol.decodeReady(Data(#"{"ready":true}"#.utf8)))
        for json in [#"{"ready":false}"#, #"{"ready":"true"}"#, "[]"] {
            XCTAssertThrowsError(try WorkerProtocol.decodeReady(Data(json.utf8))) { error in
                XCTAssertEqual(error as? PinyinWorkerError, .invalidResponse)
            }
        }
    }

    func testResponseSizeLimitIncludesTheFinalPayloadByte() throws {
        let maximum = WorkerProtocol.maximumResponseBytes
        var complete = Data(repeating: 32, count: maximum)
        complete.append(10)
        XCTAssertEqual(try WorkerProtocol.takeFrame(from: &complete)?.count, maximum)
        XCTAssertTrue(complete.isEmpty)
        let oversized = Data(repeating: 32, count: maximum + 1)
        XCTAssertThrowsError(try WorkerProtocol.decodeCandidates(oversized, pinyin: "nihao")) { error in
            XCTAssertEqual(error as? PinyinWorkerError, .responseTooLarge)
        }
        XCTAssertThrowsError(try WorkerProtocol.decodeReady(oversized)) { error in
            XCTAssertEqual(error as? PinyinWorkerError, .responseTooLarge)
        }
        var oversizedFrame = oversized
        oversizedFrame.append(10)
        XCTAssertThrowsError(try WorkerProtocol.takeFrame(from: &oversizedFrame)) { error in
            XCTAssertEqual(error as? PinyinWorkerError, .responseTooLarge)
        }
        XCTAssertEqual(oversizedFrame.count, maximum + 2, "A rejected frame is not consumed")
    }

    func testPartialAndCoalescedFramesDoNotLoseBytes() throws {
        var buffer = Data("first".utf8)
        XCTAssertNil(try WorkerProtocol.takeFrame(from: &buffer))
        buffer.append(contentsOf: "\nsecond\npartial".utf8)
        XCTAssertEqual(try WorkerProtocol.takeFrame(from: &buffer), Data("first".utf8))
        XCTAssertEqual(try WorkerProtocol.takeFrame(from: &buffer), Data("second".utf8))
        XCTAssertNil(try WorkerProtocol.takeFrame(from: &buffer))
        XCTAssertEqual(buffer, Data("partial".utf8))
    }
}
