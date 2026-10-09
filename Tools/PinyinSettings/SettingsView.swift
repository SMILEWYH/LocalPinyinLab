import SwiftUI
import PinyinInfrastructure

enum SettingsPage: String, CaseIterable, Identifiable {
    case guide, languagePacks
    var id: String { rawValue }
    var title: String {
        switch self {
        case .guide: return "使用说明"
        case .languagePacks: return "语言包"
        }
    }
    var symbol: String {
        switch self {
        case .guide: return "keyboard"
        case .languagePacks: return "character.bubble"
        }
    }
    var sidebarIdentifier: String {
        "settings-sidebar-" + (self == .languagePacks ? "language-packs" : rawValue)
    }
}

@MainActor
private final class SettingsNavigation: ObservableObject {
    @Published var selectedPage: SettingsPage?
    init(initialPage: SettingsPage) { selectedPage = initialPage }
}

struct SettingsRootView: View {
    @StateObject private var navigation: SettingsNavigation
    @StateObject private var languagePacks = LanguagePacksModel()
    @StateObject private var speechShortcut = SpeechShortcutSettingsModel()

    init(initialPage: SettingsPage) {
        _navigation = StateObject(wrappedValue: SettingsNavigation(initialPage: initialPage))
    }

    var body: some View {
        // Keep the shared model above navigation so both pages use current preferences.
        let languagePacks = self.languagePacks
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle").font(.title2).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("目录").font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("settings-sidebar-title")
                }
                .padding(.horizontal, 18).padding(.top, 24).padding(.bottom, 18)
                List(SettingsPage.allCases, selection: $navigation.selectedPage) { page in
                    Label(page.title, systemImage: page.symbol)
                        .padding(.vertical, 3)
                        .tag(page)
                        .accessibilityIdentifier(page.sidebarIdentifier)
                }
                .listStyle(.sidebar)
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text("版本 \(version)").font(.caption).foregroundStyle(.secondary)
                        .padding(18).accessibilityIdentifier("settings-version")
                }
            }
            .frame(width: 190)
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            Group {
                switch navigation.selectedPage ?? .guide {
                case .guide:
                    UsageGuideView(model: languagePacks, speechShortcut: speechShortcut,
                                   openLanguagePacks: { navigation.selectedPage = .languagePacks })
                case .languagePacks:
                    LanguagePacksView(model: languagePacks)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await languagePacks.checkAllAvailability()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(
            for: TranslationPreferences.didChangeNotification, object: TranslationPreferences.notificationObject as NSString)) { _ in
                languagePacks.refreshFromPreferences()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            languagePacks.refreshFromPreferences()
            speechShortcut.refreshFromPreferences()
            Task { await languagePacks.checkAllAvailability(restarting: true) }
        }
        .onReceive(DistributedNotificationCenter.default().publisher(
            for: SpeechShortcutPreferences.didChangeNotification, object: SpeechShortcutPreferences.notificationObject as NSString)) { _ in
                speechShortcut.refreshFromPreferences()
        }
    }
}

struct SettingsPageContent<Content: View>: View {
    let title: String
    let subtitle: String
    let identifier: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title).font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier(identifier)
                    Text(subtitle).foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)
                content()
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SettingsCard<Content: View, HeaderAction: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let headerAction: () -> HeaderAction
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(title, systemImage: symbol).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                headerAction()
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor).opacity(0.35)))
    }
}

extension SettingsCard where HeaderAction == EmptyView {
    init(title: String, symbol: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, symbol: symbol, headerAction: { EmptyView() }, content: content)
    }
}
