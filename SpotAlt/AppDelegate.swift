import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let locationStore = SearchLocationStore()
    private lazy var filenameIndex = FilenameIndex(locationStore: locationStore)
    private lazy var searchPanelController = SearchPanelController(
        filenameIndex: filenameIndex,
        locationStore: locationStore
    )
    private lazy var indexManagerWindowController = IndexManagerWindowController(
        locationStore: locationStore,
        filenameIndex: filenameIndex
    )
    private let settingsWindowController = SettingsWindowController()

    private var statusItem: NSStatusItem?
    private var globalHotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        searchPanelController.onOpenIndexManager = { [weak self] in
            self?.indexManagerWindowController.show()
        }
        indexManagerWindowController.onReturnToSearch = { [weak self] in
            self?.searchPanelController.show()
        }
        settingsWindowController.onReturnToSearch = { [weak self] in
            self?.searchPanelController.show()
        }
        configureStatusItem()
        registerInitialShortcut()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: "SpotAlt"
        )
        image?.isTemplate = true

        item.button?.image = image
        item.button?.imagePosition = .imageLeading
        item.button?.title = " SpotAlt"
        item.button?.toolTip = "Open the SpotAlt menu"
        item.button?.setAccessibilityLabel("SpotAlt")

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Open SpotAlt",
            action: #selector(openSpotAlt),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Index Manager…",
            action: #selector(openIndexManager),
            keyEquivalent: "i"
        )
        menu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit SpotAlt",
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
        alert.messageText = "SpotAlt could not register Option-Space"
        alert.informativeText = "Another application may already use this shortcut. You can still open SpotAlt from the menu bar.\n\n\(error.localizedDescription)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func openSpotAlt() {
        searchPanelController.show()
    }

    @objc private func openSettings() {
        settingsWindowController.show()
    }

    @objc private func openIndexManager() {
        indexManagerWindowController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
