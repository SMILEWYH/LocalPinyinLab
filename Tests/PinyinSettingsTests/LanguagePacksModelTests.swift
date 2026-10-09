import Foundation
import PinyinCore
import PinyinInfrastructure
import Testing
@testable import PinyinSettings

@Suite("Language pack settings navigation", .timeLimit(.minutes(1)))
@MainActor
struct LanguagePacksModelTests {
    @Test("Preparing opens system language management without changing installation or preference")
    func preparationOnlyOpensSystemSettings() async {
        let reader = StatusReader()
        let opener = PreparationSettingsOpener()
        let model = LanguagePacksModel(statusReader: reader.read, settingsOpener: opener.open)
        await model.checkAllAvailability()
        let language = model.targetLanguage
        let savedLanguage = TranslationPreferences.targetLanguage
        let statuses = model.statuses
        let readCount = reader.readCount

        #expect(model.canPrepare)
        #expect(opener.urls.isEmpty)
        model.prepare()

        #expect(opener.urls.map(\.absoluteString) == [
            "x-apple.systempreferences:com.apple.Localization-Settings.extension?translation"
        ])
        #expect(model.statuses == statuses)
        #expect(!model.isInstalled(language))
        #expect(model.statusText(for: language) == "待准备")
        #expect(model.phase == .needsPreparation)
        #expect(model.targetLanguage == language)
        #expect(TranslationPreferences.targetLanguage == savedLanguage)
        #expect(reader.readCount == readCount)
        #expect(!model.isBusy)
        #expect(model.canPrepare)
        #expect(model.preparationSettingsError == nil)

        // Navigation does not hold a session open or lock the prepare button.
        model.prepare()
        #expect(opener.urls.count == 2)
        #expect(!model.isBusy)
        #expect(model.canPrepare)
    }

    @Test("Failed navigation shows a manual path and remains retryable")
    func failedNavigationCanRetry() async {
        let reader = StatusReader()
        let opener = PreparationSettingsOpener()
        opener.succeeds = false
        let model = LanguagePacksModel(statusReader: reader.read, settingsOpener: opener.open)
        await model.checkAllAvailability()
        let statuses = model.statuses

        model.prepare()

        #expect(model.preparationSettingsError?.contains("系统设置 → 通用 → 语言与地区 → 翻译语言") == true)
        #expect(model.removalSettingsError == nil)
        #expect(model.speechSettingsError == nil)
        #expect(model.statuses == statuses)
        #expect(model.phase == .needsPreparation)
        #expect(!model.isBusy)
        #expect(model.canPrepare)

        opener.succeeds = true
        model.prepare()
        #expect(opener.urls.count == 2)
        #expect(model.preparationSettingsError == nil)
        #expect(model.statuses == statuses)
        #expect(model.phase == .needsPreparation)
    }

    @Test("Ready, unsupported, or unconfirmed pairs do not open preparation settings", arguments: [
        LanguagePacksModel.PackStatus.installed, .unsupported, .unknown, .checking
    ])
    func preparationRequiresAnUnreadySupportedPair(status: LanguagePacksModel.PackStatus) async {
        let reader = StatusReader()
        reader.status = status
        let opener = PreparationSettingsOpener()
        let model = LanguagePacksModel(statusReader: reader.read, settingsOpener: opener.open)
        await model.checkAllAvailability()

        #expect(!model.canPrepare)
        model.prepare()

        #expect(opener.urls.isEmpty)
        #expect(model.preparationSettingsError == nil)
    }

    @Test("An active refresh blocks preparation even while an older unready result is visible")
    func preparationWaitsForAvailabilityCheck() async {
        let reader = StatusReader()
        let opener = PreparationSettingsOpener()
        let model = LanguagePacksModel(statusReader: reader.read, settingsOpener: opener.open)
        await model.checkAllAvailability()
        reader.pauseNextRead = true
        let previousReadCount = reader.readCount
        let refresh = Task { await model.checkAllAvailability() }
        await reader.waitForRead(after: previousReadCount)

        #expect(model.isCheckingAll)
        #expect(model.phase == .needsPreparation)
        #expect(!model.canPrepare)
        model.prepare()
        #expect(opener.urls.isEmpty)

        reader.resumeRead()
        await refresh.value
        #expect(model.canPrepare)
    }

    @Test("Returning from settings follows confirmed system state")
    func returningFromSettingsNeedsActualInstallation() async {
        let reader = StatusReader()
        let opener = PreparationSettingsOpener()
        let model = LanguagePacksModel(statusReader: reader.read, settingsOpener: opener.open)
        await model.checkAllAvailability()
        let language = model.targetLanguage
        model.prepare()

        // Returning without installing keeps preparation available.
        await model.checkAllAvailability()
        #expect(!model.isReady)
        #expect(model.canPrepare)
        #expect(model.statuses[language] == .notInstalled)

        reader.status = .installed
        reader.pauseNextRead = true
        let previousReadCount = reader.readCount
        let refresh = Task { await model.checkAllAvailability() }
        await reader.waitForRead(after: previousReadCount)
        #expect(!model.isReady)
        #expect(!model.isInstalled(language))

        reader.resumeRead()
        await refresh.value
        #expect(model.isReady)
        #expect(model.isInstalled(language))
        #expect(!model.canPrepare)
        #expect(!model.isBusy)
        #expect(opener.urls.count == 1)
    }

    @Test("Installation confirmed after manual navigation clears an earlier launch error")
    func confirmedInstallationClearsNavigationError() async {
        let reader = StatusReader()
        let opener = PreparationSettingsOpener()
        opener.succeeds = false
        let model = LanguagePacksModel(statusReader: reader.read, settingsOpener: opener.open)
        await model.checkAllAvailability()
        model.prepare()
        #expect(model.preparationSettingsError != nil)

        reader.status = .installed
        await model.checkAllAvailability()

        #expect(model.isReady)
        #expect(model.preparationSettingsError == nil)
        #expect(opener.urls.count == 1)
    }

    @Test("A cancelled scan releases the UI and cannot overwrite a newer result")
    func cancelledScanCannotOverwriteNewScan() async {
        let reader = StatusReader()
        let opener = PreparationSettingsOpener()
        let model = LanguagePacksModel(statusReader: reader.read, settingsOpener: opener.open)
        reader.pauseNextRead = true
        let refresh = Task { await model.checkAllAvailability() }
        await reader.waitForRead(after: 0)
        #expect(model.isBusy)

        refresh.cancel()
        // Completion must not depend on the non-cooperative system read.
        await refresh.value
        #expect(!model.isBusy)
        #expect(model.statuses.values.allSatisfy { $0 == .unknown })
        #expect(reader.isPaused)

        reader.status = .installed
        await model.checkAllAvailability()
        let currentStatuses = model.statuses
        #expect(model.isReady)

        // The old system read may ignore cancellation and complete much later.
        reader.resumeRead(returning: .notInstalled)
        await reader.waitForPausedReadReturn()
        #expect(model.statuses == currentStatuses)
        #expect(model.isReady)
        #expect(model.checkedCount == TranslationLanguage.allCases.count)
        #expect(!model.isBusy)
        #expect(opener.urls.isEmpty)
    }

    @Test("A foreground refresh rereads languages checked before system settings changed")
    func foregroundRefreshStartsAFreshScan() async {
        let reader = StatusReader()
        reader.pauseAtRead = 2
        let model = LanguagePacksModel(statusReader: reader.read, settingsOpener: { _ in false })
        let original = Task { await model.checkAllAvailability() }
        await reader.waitForRead(after: 1)
        #expect(model.statuses[.english] == .notInstalled)

        // English was checked before the user installed its model in System Settings.
        reader.status = .installed
        await model.checkAllAvailability(restarting: true)
        await original.value
        #expect(reader.isPaused)
        #expect(reader.readsByLanguage[.english] == 2)
        #expect(model.statuses.values.allSatisfy { $0 == .installed })
        #expect(model.checkedCount == TranslationLanguage.allCases.count)

        reader.resumeRead(returning: .notInstalled)
        await reader.waitForPausedReadReturn()
        #expect(model.statuses.values.allSatisfy { $0 == .installed })
        #expect(!model.isBusy)
    }

    @Test("Cancelling a shared scan releases every waiter before the system read returns")
    func explicitCancellationReleasesSharedWaiters() async {
        let reader = StatusReader()
        reader.pauseNextRead = true
        let model = LanguagePacksModel(statusReader: reader.read, settingsOpener: { _ in false })
        let first = Task { await model.checkAllAvailability() }
        await reader.waitForRead(after: 0)
        var secondStarted = false
        let second = Task {
            secondStarted = true
            await model.checkAllAvailability()
        }
        while !secondStarted { await Task.yield() }

        model.cancelAvailabilityCheck()
        await first.value
        await second.value
        #expect(reader.readCount == 1)
        #expect(reader.isPaused)
        #expect(!model.isBusy)
        #expect(model.scanError == nil)

        reader.resumeRead()
        await reader.waitForPausedReadReturn()
        #expect(model.checkedCount == 0)
        #expect(model.statuses.values.allSatisfy { $0 == .unknown })
    }

    @Test("A timeout releases a non-cooperative read, invalidates unread states, and permits retry")
    func timedOutScanCanRetryWithoutWaitingForOldReader() async {
        let reader = StatusReader()
        reader.status = .installed
        let model = LanguagePacksModel(statusReader: reader.read, settingsOpener: { _ in false },
                                      scanTimeout: .milliseconds(150))
        await model.checkAllAvailability()
        #expect(model.isReady)
        reader.pauseNextRead = true

        await model.checkAllAvailability()
        #expect(reader.isPaused)
        #expect(!model.isBusy)
        #expect(model.scanError?.contains("超时") == true)
        #expect(model.statuses.values.allSatisfy { $0 == .unknown })
        #expect(!model.canRequestRemoval)

        await model.checkAllAvailability()
        #expect(model.scanError == nil)
        #expect(model.isReady)
        #expect(model.checkedCount == TranslationLanguage.allCases.count)

        reader.resumeRead(returning: .notInstalled)
        await reader.waitForPausedReadReturn()
        #expect(model.statuses.values.allSatisfy { $0 == .installed })
        #expect(model.checkedCount == TranslationLanguage.allCases.count)
        #expect(model.scanError == nil)
    }
}

@MainActor
private final class PreparationSettingsOpener {
    var succeeds = true
    private(set) var urls: [URL] = []

    func open(_ url: URL) -> Bool {
        urls.append(url)
        return succeeds
    }
}

/// Controls status replies without downloading packs or changing preferences.
@MainActor
private final class StatusReader {
    var status: LanguagePacksModel.PackStatus = .notInstalled
    var pauseNextRead = false
    var pauseAtRead: Int?
    private(set) var readCount = 0
    private(set) var readsByLanguage: [TranslationLanguage: Int] = [:]
    private var pausedReadReturned = false
    private var readWaiter: CheckedContinuation<Void, Never>?
    private var pausedRead: CheckedContinuation<LanguagePacksModel.PackStatus, Never>?
    var isPaused: Bool { pausedRead != nil }

    func read(_ language: TranslationLanguage) async -> LanguagePacksModel.PackStatus {
        readCount += 1
        readsByLanguage[language, default: 0] += 1
        if pauseNextRead || pauseAtRead == readCount {
            pauseNextRead = false
            let result = await withCheckedContinuation { continuation in
                pausedRead = continuation
                announceRead()
            }
            pausedReadReturned = true
            return result
        }
        announceRead()
        return status
    }

    func waitForRead(after previousReadCount: Int) async {
        guard readCount <= previousReadCount else { return }
        await withCheckedContinuation { readWaiter = $0 }
    }

    func resumeRead(returning result: LanguagePacksModel.PackStatus? = nil) {
        let continuation = pausedRead
        pausedRead = nil
        continuation?.resume(returning: result ?? status)
    }

    func waitForPausedReadReturn() async {
        while !pausedReadReturned { await Task.yield() }
    }

    private func announceRead() {
        let continuation = readWaiter
        readWaiter = nil
        continuation?.resume()
    }
}
