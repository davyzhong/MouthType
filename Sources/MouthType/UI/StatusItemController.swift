import AppKit

final class StatusItemController {
    private let statusItem: NSStatusItem
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        configureButton()
        buildMenu()
    }

    private func configureButton() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "MouthType")
            button.toolTip = "MouthType"
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "显示悬浮窗", action: #selector(AppDelegate.showCapsule), keyEquivalent: "")
        showItem.target = appDelegate
        menu.addItem(showItem)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        settingsItem.target = appDelegate
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "关于 MouthType", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        aboutItem.target = nil
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 MouthType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = nil
        menu.addItem(quitItem)

        statusItem.menu = menu
    }
}
