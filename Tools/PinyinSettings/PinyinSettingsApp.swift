import AppKit
import SwiftUI

@main
struct PinyinSettingsApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = SettingsAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

/// Retains one window so closing and reopening the app never creates duplicates.
@MainActor
private final class SettingsAppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        showSettingsWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func showSettingsWindow() {
        if settingsWindow == nil {
            let initialPage: SettingsPage = CommandLine.arguments.contains("--language-packs") ? .languagePacks : .guide
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "拼音设置"
            window.setAccessibilityIdentifier("settings-window")
            window.contentMinSize = NSSize(width: 740, height: 540)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsRootView(initialPage: initialPage))
            window.center()
            settingsWindow = window
        }
        if settingsWindow?.isMiniaturized == true { settingsWindow?.deminiaturize(nil) }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }

    private func installMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu(title: "拼音设置")
        appMenu.addItem(withTitle: "隐藏拼音设置", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出拼音设置", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        menu.addItem(appItem)

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        menu.addItem(editItem)

        let windowMenu = NSMenu(title: "窗口")
        let reopen = windowMenu.addItem(withTitle: "显示拼音设置", action: #selector(showSettingsWindow), keyEquivalent: "0")
        reopen.target = self
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApplication.shared.mainMenu = menu
        NSApplication.shared.windowsMenu = windowMenu
    }
}
