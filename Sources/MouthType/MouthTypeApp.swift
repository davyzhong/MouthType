import AppKit
import os
import SwiftUI

private let appLog = Logger(subsystem: "com.mouthtype", category: "App")

@main
struct MouthTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState.shared
    private let uiTestConfiguration = UITestConfiguration.current
    private var floatingCapsule: FloatingCapsuleWindow?
    private var statusItemController: StatusItemController?
    private var hotkeyMonitor: HotkeyMonitor?
    private var settingsWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        uiTestConfiguration.applyLaunchState(to: appState)

        // Build app menu bar
        buildMenuBar()

        if uiTestConfiguration.shouldShowFloatingCapsuleWindow {
            floatingCapsule = FloatingCapsuleWindow(appState: appState)
            floatingCapsule?.show()
        }

        if uiTestConfiguration.shouldCreateStatusItem {
            statusItemController = StatusItemController(appDelegate: self)
        }

        if uiTestConfiguration.shouldInstallHotkeyMonitor {
            hotkeyMonitor = HotkeyMonitor(appState: appState)
        }

        if uiTestConfiguration.shouldShowOnboarding {
            showOnboarding()
        } else if uiTestConfiguration.isEnabled {
            openSettings()
        } else if !AppSettings.shared.hasCompletedOnboarding {
            // 首次启动时显示引导流程
            showOnboarding()
        }

        appLog.info("启动成功")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyMonitor?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    @objc func showCapsule() {
        floatingCapsule?.show()
    }

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        if let existing = settingsWindowController {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        hostingController.view.setAccessibilityIdentifier("settings.root")

        let window = NSWindow(contentViewController: hostingController)
        window.identifier = NSUserInterfaceItemIdentifier("settings.window")
        window.setAccessibilityIdentifier("settings.window")
        window.title = "MouthType 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 480))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        let controller = NSWindowController(window: window)
        self.settingsWindowController = controller
        window.makeKeyAndOrderFront(nil)
    }

    @objc func showOnboarding() {
        NSApp.activate(ignoringOtherApps: true)

        let onboardingView = OnboardingView()
        let hostingController = NSHostingController(rootView: onboardingView)
        hostingController.view.setAccessibilityIdentifier("onboarding.root")

        let window = NSWindow(contentViewController: hostingController)
        window.identifier = NSUserInterfaceItemIdentifier("onboarding.window")
        window.setAccessibilityIdentifier("onboarding.window")
        window.title = "MouthType 欢迎使用"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        let controller = NSWindowController(window: window)
        self.onboardingWindowController = controller
        window.makeKeyAndOrderFront(nil)
    }

    private func buildMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "关于 MouthType", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "隐藏 MouthType", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthersItem = NSMenuItem(title: "隐藏其他应用", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(NSMenuItem(title: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "退出 MouthType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu - required for standard text editing responder chain (Cut/Copy/Paste)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        if window == settingsWindowController?.window {
            settingsWindowController = nil
        }

        if window == onboardingWindowController?.window {
            onboardingWindowController = nil
        }
    }
}
