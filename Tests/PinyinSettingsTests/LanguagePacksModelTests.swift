import PinyinCore
import Testing
@testable import PinyinSettings

@Suite("Language pack preparation", .timeLimit(.minutes(1)))
@MainActor
struct LanguagePacksModelTests {
    @Test("Closing the download prompt leaves an uninstalled pack retryable")
    func dismissedPreparationRemainsUninstalled() async throws {
        let reader = StatusReader()
        let model = LanguagePacksModel(statusReader: reader.read)
        await model.checkAllAvailability()
        #expect(model.canPrepare)

        model.prepare()
        let ticket = try #require(model.preparation)
        #expect(model.isPreparing)
        let previousReadCount = reader.readCount
        model.finishedPreparation(ticket)

        #expect(model.preparation == nil)
        #expect(!model.isReady)
        #expect(!model.isInstalled(ticket.language))
        // Wait for the scheduled refresh to start before joining its scan.
        await reader.waitForRead(after: previousReadCount)
        await model.checkAllAvailability()

        #expect(model.statuses[ticket.language] == .notInstalled)
        #expect(model.phase == .needsPreparation)
        #expect(model.canPrepare)
        #expect(!model.isBusy)
    }

    @Test("A stale success or failure cannot finish a newer preparation")
    func previousAttemptCannotFinishRetry() async throws {
        let reader = StatusReader()
        let model = LanguagePacksModel(statusReader: reader.read)
        await model.checkAllAvailability()
        model.prepare()
        let previous = try #require(model.preparation)
        model.failedPreparation(previous)
        model.prepare()
        let current = try #require(model.preparation)
        #expect(previous.id != current.id)
        #expect(previous.language == current.language)

        model.finishedPreparation(previous)
        #expect(model.preparation == current)
        #expect(model.isPreparing)
        #expect(!model.canPrepare)

        model.failedPreparation(previous)
        #expect(model.preparation == current)
        #expect(model.isPreparing)
        #expect(!model.canPrepare)
        model.failedPreparation(current)
    }

    @Test("A failed preparation releases busy state and can be retried")
    func failedPreparationCanRetry() async throws {
        let reader = StatusReader()
        let model = LanguagePacksModel(statusReader: reader.read)
        await model.checkAllAvailability()
        model.prepare()
        let ticket = try #require(model.preparation)
        model.failedPreparation(ticket)

        #expect(model.preparation == nil)
        #expect(model.phase == .failed)
        #expect(!model.isBusy)
        #expect(model.canPrepare)
        #expect(!model.isInstalled(ticket.language))

        model.prepare()
        let retry = try #require(model.preparation)
        #expect(retry.id != ticket.id)
        #expect(model.isPreparing)
        #expect(!model.canPrepare)
        model.failedPreparation(retry)
    }

    @Test("Only a completed availability check confirms installation")
    func installationNeedsStatusConfirmation() async throws {
        let reader = StatusReader()
        let model = LanguagePacksModel(statusReader: reader.read)
        await model.checkAllAvailability()
        model.prepare()
        let ticket = try #require(model.preparation)

        reader.status = .installed
        reader.pauseNextRead = true
        let previousReadCount = reader.readCount
        model.finishedPreparation(ticket)
        #expect(!model.isReady)
        #expect(!model.isInstalled(ticket.language))

        await reader.waitForRead(after: previousReadCount)
        #expect(model.isCheckingAll)
        #expect(!model.isReady)
        #expect(!model.isInstalled(ticket.language))
        reader.resumeRead()
        await model.checkAllAvailability()

        #expect(model.statuses[ticket.language] == .installed)
        #expect(model.isReady)
        #expect(!model.isBusy)
        #expect(!model.canPrepare)
    }
}

/// Controls status replies without downloading packs or changing preferences.
@MainActor
private final class StatusReader {
    var status: LanguagePacksModel.PackStatus = .notInstalled
    var pauseNextRead = false
    private(set) var readCount = 0
    private var readWaiter: CheckedContinuation<Void, Never>?
    private var pausedRead: CheckedContinuation<LanguagePacksModel.PackStatus, Never>?

    func read(_ language: TranslationLanguage) async -> LanguagePacksModel.PackStatus {
        readCount += 1
        if pauseNextRead {
            pauseNextRead = false
            return await withCheckedContinuation { continuation in
                pausedRead = continuation
                announceRead()
            }
        }
        announceRead()
        return status
    }

    func waitForRead(after previousReadCount: Int) async {
        guard readCount <= previousReadCount else { return }
        await withCheckedContinuation { readWaiter = $0 }
    }

    func resumeRead() {
        let continuation = pausedRead
        pausedRead = nil
        continuation?.resume(returning: status)
    }

    private func announceRead() {
        let continuation = readWaiter
        readWaiter = nil
        continuation?.resume()
    }
}
