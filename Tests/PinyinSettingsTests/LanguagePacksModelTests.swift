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
        while model.isCheckingAll { await Task.yield() }
        #expect(!model.isBusy)
        #expect(model.statuses.values.allSatisfy { $0 == .unknown })

        reader.status = .installed
        await model.checkAllAvailability()
        let currentStatuses = model.statuses
        #expect(model.isReady)

        // The old system read may ignore cancellation and complete much later.
        reader.resumeRead(returning: .notInstalled)
        await refresh.value
        #expect(model.statuses == currentStatuses)
        #expect(model.isReady)
        #expect(model.checkedCount == TranslationLanguage.allCases.count)
        #expect(!model.isBusy)
        #expect(opener.urls.isEmpty)
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

    func resumeRead(returning result: LanguagePacksModel.PackStatus? = nil) {
        let continuation = pausedRead
        pausedRead = nil
        continuation?.resume(returning: result ?? status)
    }

    private func announceRead() {
        let continuation = readWaiter
        readWaiter = nil
        continuation?.resume()
    }
}
