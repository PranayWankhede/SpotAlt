import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let searchPanelController = SearchPanelController()
    private let settingsWindowController = SettingsWindowController()

    private var statusItem: NSStatusItem?
    private var globalHotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        registerInitialShortcut()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: "Vez"
        )
        item.button?.toolTip = "Vez"

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Open Vez",
            action: #selector(openVez),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Vez",
            action: #selector(quit),
            keyEquivalent: "q"
        )

        for menuItem in menu.items {
            menuItem.target = self
        }

        item.menu = menu
        statusItem = item
    }

    private func registerInitialShortcut() {
        do {
            globalHotKey = try GlobalHotKey(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(optionKey)
            ) { [weak self] in
                self?.searchPanelController.toggle()
            }
        } catch {
            presentShortcutRegistrationError(error)
        }
    }

    private func presentShortcutRegistrationError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Vez could not register Option-Space"
        alert.informativeText = "Another application may already use this shortcut. You can still open Vez from the menu bar.\n\n\(error.localizedDescription)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func openVez() {
        searchPanelController.show()
    }

    @objc private func openSettings() {
        settingsWindowController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

