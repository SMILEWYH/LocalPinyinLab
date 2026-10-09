import AppKit
import SwiftUI
import Translation
import PinyinCore
import PinyinInfrastructure

@MainActor
final class LanguagePacksModel: ObservableObject {
    enum Phase { case checking, needsPreparation, ready, unsupported, unknown }
    enum PackStatus: Equatable, Sendable { case checking, installed, notInstalled, unsupported, unknown }

    typealias StatusReader = @MainActor @Sendable (TranslationLanguage) async -> PackStatus
    typealias SettingsOpener = @MainActor (URL) -> Bool

    @Published private(set) var targetLanguage = TranslationPreferences.targetLanguage
    @Published private(set) var phase: Phase = .unknown
    @Published private(set) var voiceName: String?
    @Published private(set) var selectionError: String?
    @Published private(set) var speechSettingsError: String?
    @Published private(set) var removalSettingsError: String?
    @Published private(set) var preparationSettingsError: String?
    @Published private(set) var scanError: String?
    @Published private(set) var statuses = Dictionary(
        uniqueKeysWithValues: TranslationLanguage.allCases.map { ($0, PackStatus.unknown) })
    @Published private(set) var isCheckingAll = false
    @Published private(set) var checkedCount = 0

    private let readStatus: StatusReader
    private let openSettings: SettingsOpener
    private let scanTimeout: Duration
    private var scanID: UUID?
    private var scanTask: Task<Void, Never>?
    private var scanTimeoutTask: Task<Void, Never>?
    private var scanWaiters: [CheckedContinuation<Void, Never>] = []
    private var checkedLanguages: Set<TranslationLanguage> = []

    init(statusReader: StatusReader? = nil, settingsOpener: SettingsOpener? = nil,
         scanTimeout: Duration = .seconds(15)) {
        readStatus = statusReader ?? Self.systemStatus
        openSettings = settingsOpener ?? { NSWorkspace.shared.open($0) }
        self.scanTimeout = scanTimeout
        refreshVoice()
    }

    var isBusy: Bool { isCheckingAll }
    var isReady: Bool { phase == .ready }
    var canPrepare: Bool { !isCheckingAll && phase == .needsPreparation }
    var canRequestRemoval: Bool { isReady && !isBusy }
    var installedCount: Int { statuses.values.filter { $0 == .installed }.count }
    var scanSummary: String {
        let progress = "\(checkedCount)/\(TranslationLanguage.allCases.count)"
        return "\(isCheckingAll ? "正在检查" : "已检查") \(progress)，已安装 \(installedCount) 种"
    }

    func isInstalled(_ language: TranslationLanguage) -> Bool { statuses[language] == .installed }

    func statusText(for language: TranslationLanguage) -> String {
        switch statuses[language] ?? .unknown {
        case .checking: return "正在检查"
        case .installed: return "已安装"
        case .notInstalled: return "待准备"
        case .unsupported: return "系统暂不支持"
        case .unknown: return "状态未知"
        }
    }

    var message: String {
        let language = targetLanguage.displayName
        switch phase {
        case .checking: return "正在检查中文 → \(language)翻译…"
        case .needsPreparation: return "中文 → \(language)翻译尚待准备"
        case .ready: return "中文 → \(language)离线翻译已就绪"
        case .unsupported: return "当前系统暂不支持中文 → \(language)翻译"
        case .unknown: return "暂时无法确认中文 → \(language)翻译是否就绪"
        }
    }

    var detail: String {
        switch phase {
        case .checking: return "检查只读取系统语言包状态，不会下载。"
        case .needsPreparation:
            return isCheckingAll ? "正在检查全部目标语言，检查结束后可准备当前翻译。" : "点击「准备语言包」打开系统设置中的翻译语言列表，自行下载所需语言；返回后会重新检查。"
        case .ready: return "中文候选将显示\(targetLanguage.displayName)译文，朗读也使用该语言。"
        case .unsupported: return "可选择其他目标语言；中文拼音输入仍可正常使用。"
        case .unknown: return "请重新检查。确认系统支持后，才能准备对应翻译。"
        }
    }

    var symbol: String {
        switch phase {
        case .ready: return "checkmark.circle.fill"
        case .unsupported, .unknown: return "exclamationmark.circle"
        default: return "arrow.down.circle"
        }
    }

    var voiceMessage: String {
        if let voiceName { return "\(targetLanguage.displayName)声音：\(voiceName)" }
        return "尚未找到本机\(targetLanguage.displayName)声音"
    }

    func selectLanguage(_ language: TranslationLanguage) {
        guard language != targetLanguage else { return }
        do {
            try TranslationPreferences.setTargetLanguage(language)
        } catch {
            selectionError = "未能保存语言选择，仍使用\(targetLanguage.displayName)。请重试。"
            return
        }
        adoptLanguage(language)
    }

    /// Notifications carry no trusted settings; reread the persisted value.
    func refreshFromPreferences() {
        let saved = TranslationPreferences.targetLanguage
        if saved != targetLanguage { adoptLanguage(saved) }
        refreshVoice()
    }

    func checkAvailability() async { await checkAllAvailability() }

    /// Foreground refreshes must read states changed while another scan was running.
    func checkAllAvailability(restarting: Bool = false) async {
        guard !Task.isCancelled else { return }
        if restarting { cancelAvailabilityCheck() }
        let ticket = scanID ?? startScan()

        await withTaskCancellationHandler {
            // Do not await the reader task itself: system queries may ignore
            // cancellation. Our lifecycle owns completion of these waiters.
            await withCheckedContinuation { continuation in
                guard scanID == ticket, !Task.isCancelled else {
                    cancelScan(ticket: ticket)
                    continuation.resume()
                    return
                }
                scanWaiters.append(continuation)
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.cancelScan(ticket: ticket) }
        }
    }

    func cancelAvailabilityCheck() {
        if let ticket = scanID { cancelScan(ticket: ticket) }
    }

    private func startScan() -> UUID {
        let ticket = UUID()
        scanID = ticket
        checkedCount = 0
        checkedLanguages = []
        scanError = nil
        isCheckingAll = true
        // Keep confirmed states visible while refreshing. Unread states become
        // unknown if the scan stops early, so stale results cannot enable actions.
        for language in TranslationLanguage.allCases where statuses[language] == .unknown {
            statuses[language] = .checking
        }
        updateTargetPhase()
        refreshVoice()
        scanTask = Task { [weak self, readStatus] in
            for language in TranslationLanguage.allCases {
                guard self?.scanID == ticket, !Task.isCancelled else { return }
                let result = await readStatus(language)
                guard self?.scanID == ticket, !Task.isCancelled else { return }
                self?.recordStatus(result, for: language)
            }
            self?.finishScan(ticket: ticket)
        }
        scanTimeoutTask = Task { [weak self, scanTimeout] in
            do { try await Task.sleep(for: scanTimeout) }
            catch { return }
            guard let self, self.scanID == ticket else { return }
            self.scanError = "检查语言包超时，请重新检查。未完成的项目暂时显示为状态未知。"
            self.finishScan(ticket: ticket)
        }
        return ticket
    }

    private func recordStatus(_ result: PackStatus, for language: TranslationLanguage) {
        statuses[language] = result == .checking ? .unknown : result
        checkedLanguages.insert(language)
        checkedCount += 1
        updateTargetPhase()
    }

    private func cancelScan(ticket: UUID) {
        guard scanID == ticket else { return }
        finishScan(ticket: ticket)
    }

    private func finishScan(ticket: UUID) {
        guard scanID == ticket else { return }
        scanID = nil
        scanTask?.cancel()
        scanTask = nil
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        isCheckingAll = false
        for language in TranslationLanguage.allCases where !checkedLanguages.contains(language) {
            statuses[language] = .unknown
        }
        updateTargetPhase()
        let waiters = scanWaiters
        scanWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    func prepare() {
        guard canPrepare else { return }
        let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension?translation")!
        guard openSettings(url) else {
            preparationSettingsError = "未能打开系统设置。请前往「系统设置 → 通用 → 语言与地区 → 翻译语言」下载所需语言。"
            return
        }
        preparationSettingsError = nil
        removalSettingsError = nil
    }

    func openSpeechSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension"),
              NSWorkspace.shared.open(url) else {
            speechSettingsError = "未能打开系统设置。请手动打开「系统设置 → 辅助功能」，在语音相关设置中添加\(targetLanguage.displayName)声音。"
            return
        }
        speechSettingsError = nil
    }

    /// macOS owns these shared models and reserves direct removal for system apps.
    /// The user removes only the named foreign language in the system window.
    /// Opening that window must never imply that any language was removed.
    func openRemovalSettings(for language: TranslationLanguage) {
        guard language == targetLanguage else {
            removalSettingsError = "当前目标语言已变化，请重新打开删除入口。"
            return
        }
        guard canRequestRemoval, isInstalled(language) else {
            removalSettingsError = "语言包状态已变化，请检查完成后再试。"
            return
        }
        let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension?translation")!
        guard openSettings(url) else {
            removalSettingsError = "未能打开系统设置。请前往「系统设置 → 通用 → 语言与地区 → 翻译语言」，仅移除\(language.displayName)，保留中文语言包。"
            return
        }
        removalSettingsError = nil
    }

    private func adoptLanguage(_ language: TranslationLanguage) {
        // The all-language scan remains valid when the selected target changes.
        targetLanguage = language
        selectionError = nil
        speechSettingsError = nil
        removalSettingsError = nil
        preparationSettingsError = nil
        updateTargetPhase()
        refreshVoice()
    }

    private func updateTargetPhase() {
        let status = statuses[targetLanguage] ?? .unknown
        switch status {
        case .checking: phase = .checking
        case .installed:
            phase = .ready
            preparationSettingsError = nil
        case .notInstalled: phase = .needsPreparation
        case .unsupported: phase = .unsupported
        case .unknown: phase = .unknown
        }
    }

    private func refreshVoice() {
        voiceName = LocalSpeechPlayer.installedVoice(for: targetLanguage)?.name
    }

    private static func systemStatus(for language: TranslationLanguage) async -> PackStatus {
        let status = await AppleTranslationPolicy.availability().status(
            from: Locale.Language(identifier: "zh-Hans"),
            to: Locale.Language(identifier: language.localeIdentifier))
        switch status {
        case .installed: return .installed
        case .supported: return .notInstalled
        case .unsupported: return .unsupported
        @unknown default: return .unknown
        }
    }
}
