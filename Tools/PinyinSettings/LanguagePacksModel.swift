import AppKit
import SwiftUI
import Translation
import PinyinCore
import PinyinInfrastructure

@MainActor
final class LanguagePacksModel: ObservableObject {
    enum Phase { case checking, needsPreparation, preparing, ready, failed, unsupported, unknown }
    enum PackStatus: Equatable, Sendable { case checking, installed, notInstalled, unsupported, unknown }
    struct Preparation: Sendable, Equatable {
        let id: UUID
        let language: TranslationLanguage
    }

    typealias StatusReader = @MainActor @Sendable (TranslationLanguage) async -> PackStatus

    @Published private(set) var targetLanguage = TranslationPreferences.targetLanguage
    @Published private(set) var phase: Phase = .unknown
    @Published private(set) var preparation: Preparation?
    @Published private(set) var voiceName: String?
    @Published private(set) var selectionError: String?
    @Published private(set) var speechSettingsError: String?
    @Published private(set) var statuses = Dictionary(
        uniqueKeysWithValues: TranslationLanguage.allCases.map { ($0, PackStatus.unknown) })
    @Published private(set) var isCheckingAll = false
    @Published private(set) var checkedCount = 0

    private let readStatus: StatusReader
    private var scanID: UUID?
    private var scanTask: Task<Void, Never>?
    private var failedLanguages: Set<TranslationLanguage> = []

    init(statusReader: StatusReader? = nil) {
        readStatus = statusReader ?? Self.systemStatus
        refreshVoice()
    }

    var isBusy: Bool { isCheckingAll || isPreparing }
    var isPreparing: Bool { phase == .preparing }
    var isReady: Bool { phase == .ready }
    var canPrepare: Bool { !isCheckingAll && (phase == .needsPreparation || phase == .failed) }
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
        case .notInstalled: return "未安装"
        case .unsupported: return "系统暂不支持"
        case .unknown: return "状态未知"
        }
    }

    var message: String {
        let language = targetLanguage.displayName
        switch phase {
        case .checking: return "正在检查中文 → \(language)语言包…"
        case .needsPreparation: return "尚未准备\(language)语言包"
        case .preparing: return "正在准备\(language)语言包…"
        case .ready: return "中文 → \(language)离线翻译已就绪"
        case .failed: return "\(language)语言包准备未完成"
        case .unsupported: return "当前系统暂不支持中文 → \(language)翻译"
        case .unknown: return "暂时无法确认\(language)语言包状态"
        }
    }

    var detail: String {
        switch phase {
        case .checking: return "检查只读取系统语言包状态，不会下载。"
        case .needsPreparation:
            return isCheckingAll ? "正在检查全部语言包，检查结束后可准备当前语言。" : "点击「准备语言包」，再按 macOS 提示下载。中文拼音输入可继续使用。"
        case .preparing: return "请按 macOS 提示操作；关闭提示后可重新准备或切换目标语言。"
        case .ready: return "中文候选将显示\(targetLanguage.displayName)译文，朗读也使用该语言。"
        case .failed: return "可能是下载中断或系统提示被取消。请检查网络，然后重试准备。"
        case .unsupported: return "可选择其他目标语言；中文拼音输入仍可正常使用。"
        case .unknown: return "请重新检查。确认系统支持后，才能准备对应语言包。"
        }
    }

    var symbol: String {
        switch phase {
        case .ready: return "checkmark.circle.fill"
        case .failed, .unsupported, .unknown: return "exclamationmark.circle"
        default: return "arrow.down.circle"
        }
    }

    var voiceMessage: String {
        if let voiceName { return "\(targetLanguage.displayName)声音：\(voiceName)" }
        return "尚未找到本机\(targetLanguage.displayName)声音"
    }

    func selectLanguage(_ language: TranslationLanguage) {
        guard !isPreparing, language != targetLanguage else { return }
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

    func checkAllAvailability() async {
        guard !isPreparing, !Task.isCancelled else { return }
        let ticket: UUID
        let task: Task<Void, Never>
        if let currentID = scanID, let currentTask = scanTask {
            ticket = currentID
            task = currentTask
        } else {
            ticket = UUID()
            scanID = ticket
            checkedCount = 0
            isCheckingAll = true
            // Keep confirmed states visible while refreshing. Only languages
            // without a previous result need a temporary checking state.
            for language in TranslationLanguage.allCases where statuses[language] == .unknown {
                statuses[language] = .checking
            }
            updateTargetPhase()
            refreshVoice()
            task = Task { [weak self] in await self?.scanAll(ticket: ticket) }
            scanTask = task
        }

        await withTaskCancellationHandler {
            await task.value
        } onCancel: { [weak self] in
            // The system reader need not cooperate with cancellation. Clear
            // busy independently, and reject its eventual reply by ticket.
            Task { @MainActor in self?.cancelScan(ticket: ticket) }
        }
    }

    private func scanAll(ticket: UUID) async {
        defer { finishScan(ticket: ticket) }
        for language in TranslationLanguage.allCases {
            guard scanID == ticket, !Task.isCancelled else { return }
            let result = await readStatus(language)
            guard scanID == ticket, !Task.isCancelled else { return }
            statuses[language] = result == .checking ? .unknown : result
            checkedCount += 1
            if result == .installed { failedLanguages.remove(language) }
            updateTargetPhase()
        }
    }

    private func cancelScan(ticket: UUID) {
        guard scanID == ticket else { return }
        scanTask?.cancel()
        finishScan(ticket: ticket)
    }

    private func finishScan(ticket: UUID) {
        guard scanID == ticket else { return }
        scanID = nil
        scanTask = nil
        isCheckingAll = false
        for language in TranslationLanguage.allCases where statuses[language] == .checking {
            statuses[language] = .unknown
        }
        updateTargetPhase()
    }

    func prepare() {
        guard canPrepare else { return }
        failedLanguages.remove(targetLanguage)
        preparation = Preparation(id: UUID(), language: targetLanguage)
        phase = .preparing
    }

    func finishedPreparation(_ ticket: Preparation) {
        guard preparation == ticket, targetLanguage == ticket.language, isPreparing else { return }
        // Closing the prompt, or a download already running in the background,
        // can return successfully. Only the availability scan confirms installation.
        failedLanguages.remove(ticket.language)
        preparation = nil
        updateTargetPhase()
        refreshVoice()
        Task { [weak self] in await self?.checkAllAvailability() }
    }

    func failedPreparation(_ ticket: Preparation) {
        guard preparation == ticket, targetLanguage == ticket.language, isPreparing else { return }
        failedLanguages.insert(ticket.language)
        phase = .failed
        preparation = nil
    }

    func openSpeechSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension"),
              NSWorkspace.shared.open(url) else {
            speechSettingsError = "未能打开系统设置。请手动打开「系统设置 → 辅助功能」，在语音相关设置中添加\(targetLanguage.displayName)声音。"
            return
        }
        speechSettingsError = nil
    }

    private func adoptLanguage(_ language: TranslationLanguage) {
        // A preference change from another settings process invalidates only
        // preparation. The all-language scan remains valid for its new target.
        preparation = nil
        targetLanguage = language
        selectionError = nil
        speechSettingsError = nil
        updateTargetPhase()
        refreshVoice()
    }

    private func updateTargetPhase() {
        guard preparation == nil else { return }
        let status = statuses[targetLanguage] ?? .unknown
        if failedLanguages.contains(targetLanguage), status != .installed, status != .unsupported {
            phase = .failed
            return
        }
        switch status {
        case .checking: phase = .checking
        case .installed: phase = .ready
        case .notInstalled: phase = .needsPreparation
        case .unsupported: phase = .unsupported
        case .unknown: phase = .unknown
        }
    }

    private func refreshVoice() {
        voiceName = LocalSpeechPlayer.installedVoice(for: targetLanguage)?.name
    }

    private static func systemStatus(for language: TranslationLanguage) async -> PackStatus {
        let status = await LanguageAvailability().status(
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
