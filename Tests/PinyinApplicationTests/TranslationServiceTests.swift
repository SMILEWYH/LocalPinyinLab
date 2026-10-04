import Foundation
import TestSupport
import PinyinApplication

@MainActor
private final class StubTranslationBackend: TranslationBackend {
    var calls: [[TranslationRequest]] = []
    var respond: ([TranslationRequest]) throws -> [TranslationResponse] = { requests in
        requests.map { TranslationResponse(identifier: $0.identifier, text: "English: " + $0.source) }
    }

    func translations(for requests: [TranslationRequest]) async throws -> [TranslationResponse] {
        calls.append(requests)
        return try respond(requests)
    }
}

/// Deliberately ignores cancellation so tests exercise the service's own guard.
@MainActor
private final class ControlledTranslationBackend: TranslationBackend {
    private(set) var calls: [[TranslationRequest]] = []
    private var pending: [Int: CheckedContinuation<[TranslationResponse], Error>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func translations(for requests: [TranslationRequest]) async throws -> [TranslationResponse] {
        try await withCheckedThrowingContinuation { continuation in
            let index = calls.count
            calls.append(requests)
            pending[index] = continuation
            let ready = waiters.filter { $0.0 <= calls.count }
            waiters.removeAll { $0.0 <= calls.count }
            for (_, waiter) in ready { waiter.resume() }
        }
    }

    func waitForCallCount(_ count: Int) async {
        guard calls.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func complete(_ index: Int) {
        let responses = calls[index].map {
            TranslationResponse(identifier: $0.identifier, text: "English: " + $0.source)
        }
        pending.removeValue(forKey: index)?.resume(returning: responses)
    }
}

@main
@MainActor
struct TranslationServiceTests {
    static func main() async throws {
        let suite = TranslationServiceTests()
        try await suite.testDeduplicatesRequestsAndRestoresSourceOrder()
        try await suite.testEmptyBatchDoesNotCallBackend()
        try await suite.testCacheEvictsInInsertionOrderWithoutRefreshingHits()
        try await suite.testBatchLargerThanCacheStillReturnsEveryTranslation()
        try await suite.testMissingResponseDoesNotPartiallyPopulateCache()
        try await suite.testDuplicateResponseIdentifiersAreRejectedWithoutCrash()
        try await suite.testMissingResponseIdentifierIsRejected()
        try await suite.testUnexpectedResponseIdentifierIsRejected()
        try await suite.testEmptyTranslationIsRejected()
        try await suite.testWhitespaceTranslationIsRejected()
        try await suite.testOriginalTranslationWhitespaceIsPreserved()
        try await suite.testBackendFailurePropagatesWithoutCaching()
        try await suite.testCancelledCallDoesNotUseBackend()
        try await suite.testCancellationAfterBackendResponseDoesNotPopulateCache()
        try await suite.testConcurrentEvictionCannotRemoveAnotherCallsResolvedCacheHit()
        print("PASS: 15 translation service tests (batch mapping, FIFO, malformed responses, original output, cancellation, concurrent eviction)")
    }

    func testDeduplicatesRequestsAndRestoresSourceOrder() async throws {
        let backend = StubTranslationBackend()
        backend.respond = { requests in
            requests.reversed().map {
                TranslationResponse(identifier: $0.identifier, text: "English: " + $0.source)
            }
        }
        let service = TranslationService(backend: backend)
        let translated = try await service.translate(["你好", "谢谢", "你好"])
        XCTAssertEqual(translated, ["English: 你好", "English: 谢谢", "English: 你好"])
        XCTAssertEqual(backend.calls.map { $0.map(\.source) }, [["你好", "谢谢"]])
        let cached = try await service.translate(["谢谢", "你好"])
        XCTAssertEqual(cached, ["English: 谢谢", "English: 你好"])
        XCTAssertEqual(backend.calls.count, 1)
    }

    func testEmptyBatchDoesNotCallBackend() async throws {
        let backend = StubTranslationBackend()
        let translated = try await TranslationService(backend: backend).translate([])
        XCTAssertEqual(translated, [])
        XCTAssertTrue(backend.calls.isEmpty)
    }

    func testCacheEvictsInInsertionOrderWithoutRefreshingHits() async throws {
        let backend = StubTranslationBackend()
        let service = TranslationService(backend: backend, cacheCapacity: 2)
        _ = try await service.translate(["甲", "乙"])
        _ = try await service.translate(["甲"])
        _ = try await service.translate(["丙"])
        _ = try await service.translate(["乙"])
        XCTAssertEqual(backend.calls.count, 2)
        _ = try await service.translate(["甲"])
        XCTAssertEqual(backend.calls.map { $0.map(\.source) }, [["甲", "乙"], ["丙"], ["甲"]])
    }

    func testBatchLargerThanCacheStillReturnsEveryTranslation() async throws {
        let backend = StubTranslationBackend()
        let service = TranslationService(backend: backend, cacheCapacity: 1)
        let translated = try await service.translate(["甲", "乙", "丙", "甲"])
        XCTAssertEqual(translated, ["English: 甲", "English: 乙", "English: 丙", "English: 甲"])
        _ = try await service.translate(["丙"])
        XCTAssertEqual(backend.calls.count, 1)
        _ = try await service.translate(["甲"])
        XCTAssertEqual(backend.calls.count, 2)
    }

    func testMissingResponseDoesNotPartiallyPopulateCache() async throws {
        try await assertRejectedBatch([
            TranslationResponse(identifier: "0", text: "first")
        ])
    }

    func testDuplicateResponseIdentifiersAreRejectedWithoutCrash() async throws {
        try await assertRejectedBatch([
            TranslationResponse(identifier: "0", text: "first"),
            TranslationResponse(identifier: "0", text: "duplicate"),
            TranslationResponse(identifier: "1", text: "second")
        ])
    }

    func testMissingResponseIdentifierIsRejected() async throws {
        try await assertRejectedBatch([
            TranslationResponse(identifier: "0", text: "first"),
            TranslationResponse(identifier: nil, text: "second")
        ])
    }

    func testUnexpectedResponseIdentifierIsRejected() async throws {
        try await assertRejectedBatch([
            TranslationResponse(identifier: "0", text: "first"),
            TranslationResponse(identifier: "1", text: "second"),
            TranslationResponse(identifier: "foreign", text: "unexpected")
        ])
    }

    func testEmptyTranslationIsRejected() async throws {
        try await assertRejectedBatch([
            TranslationResponse(identifier: "0", text: "first"),
            TranslationResponse(identifier: "1", text: "")
        ])
    }

    func testWhitespaceTranslationIsRejected() async throws {
        try await assertRejectedBatch([
            TranslationResponse(identifier: "0", text: "first"),
            TranslationResponse(identifier: "1", text: " \t\n\u{3000}")
        ])
    }

    func testOriginalTranslationWhitespaceIsPreserved() async throws {
        let backend = StubTranslationBackend()
        backend.respond = { requests in
            requests.map { TranslationResponse(identifier: $0.identifier, text: "  Hello\n") }
        }
        let service = TranslationService(backend: backend)
        let translated = try await service.translate(["你好"])
        XCTAssertEqual(translated, ["  Hello\n"])
        let cached = try await service.translate(["你好"])
        XCTAssertEqual(cached, translated)
        XCTAssertEqual(backend.calls.count, 1)
    }

    func testBackendFailurePropagatesWithoutCaching() async throws {
        let backend = StubTranslationBackend()
        let service = TranslationService(backend: backend)
        backend.respond = { _ in throw TranslationFailure.modelsNotInstalled }
        do {
            _ = try await service.translate(["你好"])
            XCTFail("Expected the missing-model failure")
        } catch TranslationFailure.modelsNotInstalled {
            // No automatic download or alternate translation is attempted.
        }
        backend.respond = { $0.map { TranslationResponse(identifier: $0.identifier, text: "Hello") } }
        let translated = try await service.translate(["你好"])
        XCTAssertEqual(translated, ["Hello"])
        XCTAssertEqual(backend.calls.count, 2)
    }

    func testCancelledCallDoesNotUseBackend() async throws {
        let backend = StubTranslationBackend()
        let service = TranslationService(backend: backend)
        let task = Task { @MainActor in try await service.translate(["你好"]) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        XCTAssertTrue(backend.calls.isEmpty)
    }

    func testCancellationAfterBackendResponseDoesNotPopulateCache() async throws {
        let backend = ControlledTranslationBackend()
        let service = TranslationService(backend: backend)
        let cancelled = Task { @MainActor in try await service.translate(["你好"]) }
        await backend.waitForCallCount(1)
        cancelled.cancel()
        backend.complete(0)
        do {
            _ = try await cancelled.value
            XCTFail("Expected cancellation even when backend ignores it")
        } catch is CancellationError {}
        let retry = Task { @MainActor in try await service.translate(["你好"]) }
        await backend.waitForCallCount(2)
        backend.complete(1)
        let translated = try await retry.value
        XCTAssertEqual(translated, ["English: 你好"])
        XCTAssertEqual(backend.calls.count, 2)
    }

    func testConcurrentEvictionCannotRemoveAnotherCallsResolvedCacheHit() async throws {
        let backend = ControlledTranslationBackend()
        let service = TranslationService(backend: backend, cacheCapacity: 1)
        let prime = Task { @MainActor in try await service.translate(["甲"]) }
        await backend.waitForCallCount(1)
        backend.complete(0)
        _ = try await prime.value

        let mixed = Task { @MainActor in try await service.translate(["甲", "乙"]) }
        await backend.waitForCallCount(2)
        XCTAssertEqual(backend.calls[1].map(\.source), ["乙"])
        let evict = Task { @MainActor in try await service.translate(["丙"]) }
        await backend.waitForCallCount(3)
        backend.complete(2)
        _ = try await evict.value
        backend.complete(1)
        let translated = try await mixed.value
        XCTAssertEqual(translated, ["English: 甲", "English: 乙"])
    }

    private func assertRejectedBatch(_ responses: [TranslationResponse],
                                     file: StaticString = #filePath, line: UInt = #line) async throws {
        let backend = StubTranslationBackend()
        let service = TranslationService(backend: backend, cacheCapacity: 1)
        _ = try await service.translate(["原有缓存"])
        backend.respond = { _ in responses }
        do {
            _ = try await service.translate(["甲", "乙"])
            XCTFail("Expected malformed-response failure", file: file, line: line)
        } catch TranslationFailure.invalidResponse {}
        let preserved = try await service.translate(["原有缓存"])
        XCTAssertEqual(preserved, ["English: 原有缓存"], file: file, line: line)
        XCTAssertEqual(backend.calls.count, 2, file: file, line: line)
        backend.respond = { requests in
            requests.map { TranslationResponse(identifier: $0.identifier, text: "English: " + $0.source) }
        }
        let translated = try await service.translate(["甲", "乙"])
        XCTAssertEqual(translated, ["English: 甲", "English: 乙"], file: file, line: line)
        XCTAssertEqual(backend.calls.last?.map(\.source), ["甲", "乙"], file: file, line: line)
    }
}
