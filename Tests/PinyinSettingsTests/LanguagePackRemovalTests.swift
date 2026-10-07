import Foundation
import PinyinCore
import Testing
@testable import PinyinSettings

@Suite("Language pack removal entry", .timeLimit(.minutes(1)))
@MainActor
struct LanguagePackRemovalTests {
    @Test("Opening system management preserves the confirmed installation state")
    func openingSettingsDoesNotPretendToRemoveThePack() async {
        let reader = RemovalStatusReader(status: .installed)
        let opener = SettingsOpener()
        let model = LanguagePacksModel(statusReader: reader.read, settingsOpener: opener.open)
        await model.checkAllAvailability()
        let language = model.targetLanguage
        let confirmedStatuses = model.statuses

        #expect(model.canRequestRemoval)
        model.openRemovalSettings(for: language)

        #expect(opener.urls.map(\.absoluteString) == [
            "x-apple.systempreferences:com.apple.Localization-Settings.extension?translation"
        ])
        #expect(model.statuses == confirmedStatuses)
        #expect(model.isInstalled(language))
        #expect(model.isReady)
        #expect(!model.canPrepare)
        #expect(model.removalSettingsError == nil)
    }

    @Test("Unconfirmed or unavailable packs cannot open removal settings", arguments: [
        LanguagePacksModel.PackStatus.notInstalled, .unsupported, .unknown
    ])
    func removalRequiresConfirmedInstallation(status: LanguagePacksModel.PackStatus) async {
        let reader = RemovalStatusReader(status: status)
        let opener = SettingsOpener()
        let model = LanguagePacksModel(statusReader: reader.read, settingsOpener: opener.open)
        await model.checkAllAvailability()

        #expect(!model.canRequestRemoval)
        model.openRemovalSettings(for: model.targetLanguage)

        #expect(opener.urls.isEmpty)
        #expect(model.statuses[model.targetLanguage] == status)
        #expect(model.removalSettingsError?.isEmpty == false)
    }

    @Test("A refresh blocks removal even while the previous installed result is visible")
    func removalWaitsForAnActiveAvailabilityCheck() async {
        let reader = RemovalStatusReader(status: .installed)
        let opener = SettingsOpener()
        let model = LanguagePacksModel(statusReader: reader.read, settingsOpener: opener.open)
        await model.checkAllAvailability()

        reader.pauseNextRead = true
        let previousReadCount = reader.readCount
        let refresh = Task { await model.checkAllAvailability() }
        await reader.waitForRead(after: previousReadCount)

        #expect(model.isCheckingAll)
        #expect(model.isInstalled(model.targetLanguage))
        #expect(!model.canRequestRemoval)
        model.openRemovalSettings(for: model.targetLanguage)
        #expect(opener.urls.isEmpty)

        reader.resumeRead()
        await refresh.value
        #expect(model.canRequestRemoval)
    }

    @Test("A removal request for a different language is rejected")
    func staleLanguageCannotOpenRemovalSettings() async throws {
        let reader = RemovalStatusReader(status: .installed)
        let opener = SettingsOpener()
        let model = LanguagePacksModel(statusReader: reader.read, settingsOpener: opener.open)
        await model.checkAllAvailability()
        let currentLanguage = model.targetLanguage
        let staleLanguage = try #require(TranslationLanguage.allCases.first { $0 != currentLanguage })

        #expect(model.isInstalled(staleLanguage))
        #expect(model.canRequestRemoval)
        model.openRemovalSettings(for: staleLanguage)

        #expect(opener.urls.isEmpty)
        #expect(model.targetLanguage == currentLanguage)
        #expect(model.isReady)
        #expect(model.removalSettingsError?.isEmpty == false)
    }

    @Test("Failure to open settings reports an error without changing the pack state")
    func failedSettingsLaunchCanBeRetried() async {
        let reader = RemovalStatusReader(status: .installed)
        let opener = SettingsOpener()
        opener.succeeds = false
        let model = LanguagePacksModel(statusReader: reader.read, settingsOpener: opener.open)
        await model.checkAllAvailability()
        let language = model.targetLanguage

        model.openRemovalSettings(for: language)

        #expect(model.removalSettingsError?.isEmpty == false)
        #expect(model.isInstalled(language))
        #expect(model.isReady)
        #expect(model.canRequestRemoval)

        opener.succeeds = true
        model.openRemovalSettings(for: language)
        #expect(opener.urls.count == 2)
        #expect(model.removalSettingsError == nil)
        #expect(model.isInstalled(language))
    }

    @Test("Returning from settings follows actual installation status")
    func returningFromSettingsOnlyOffersPreparationAfterConfirmedRemoval() async {
        let reader = RemovalStatusReader(status: .installed)
        let opener = SettingsOpener()
        let model = LanguagePacksModel(statusReader: reader.read, settingsOpener: opener.open)
        await model.checkAllAvailability()
        let language = model.targetLanguage
        model.openRemovalSettings(for: language)

        // Leaving system settings without removing anything keeps the pack ready.
        await model.checkAllAvailability()
        #expect(model.isReady)
        #expect(model.isInstalled(language))
        #expect(model.canRequestRemoval)
        #expect(!model.canPrepare)

        reader.status = .notInstalled
        await model.checkAllAvailability()
        #expect(model.statuses[language] == .notInstalled)
        #expect(!model.isReady)
        #expect(!model.canRequestRemoval)
        #expect(model.canPrepare)
        #expect(model.phase == .needsPreparation)
        #expect(opener.urls.count == 1)
    }
}

/// Records navigation without launching System Settings or touching real packs.
@MainActor
private final class SettingsOpener {
    var succeeds = true
    private(set) var urls: [URL] = []

    func open(_ url: URL) -> Bool {
        urls.append(url)
        return succeeds
    }
}

/// Supplies system-state changes without writing the user's language preference.
@MainActor
private final class RemovalStatusReader {
    var status: LanguagePacksModel.PackStatus
    var pauseNextRead = false
    private(set) var readCount = 0
    private var readWaiter: CheckedContinuation<Void, Never>?
    private var pausedRead: CheckedContinuation<LanguagePacksModel.PackStatus, Never>?

    init(status: LanguagePacksModel.PackStatus) { self.status = status }

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
