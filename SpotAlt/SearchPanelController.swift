import AppKit

final class SearchPanelController: NSObject, NSWindowDelegate {
    private static let panelWidth: CGFloat = 680

    var onOpenIndexManager: (() -> Void)?

    private let searchViewController: SearchViewController
    private lazy var panel: SearchPanel = makePanel()
    private var previousApplication: NSRunningApplication?
    private var isDismissing = false
    private var panelHeight: CGFloat = 68
    private var hasCreatedPanel = false

    init(filenameIndex: FilenameIndex, locationStore: SearchLocationStore) {
        searchViewController = SearchViewController(
            filenameIndex: filenameIndex,
            locationStore: locationStore
        )
        super.init()
        searchViewController.onDismiss = { [weak self] in
            self?.hide(restoringPreviousApplication: true)
        }
        searchViewController.onOpenFile = { [weak self] url in
            self?.open(url)
        }
        searchViewController.onOpenIndexManager = { [weak self] in
            self?.openIndexManager()
        }
        searchViewController.onPreferredHeightChange = { [weak self] height in
            self?.resizePanel(to: height)
        }
    }

    func toggle() {
        if panel.isVisible {
            hide(restoringPreviousApplication: true)
        } else {
            show()
        }
    }

    func show() {
        guard !panel.isVisible else {
            panel.makeKeyAndOrderFront(nil)
            searchViewController.focusSearchField()
            return
        }

        capturePreviousApplication()
        positionPanelOnActiveScreen()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async { [weak self] in
            self?.searchViewController.focusSearchField()
        }
    }

    func hide(restoringPreviousApplication: Bool) {
        guard panel.isVisible, !isDismissing else { return }
        isDismissing = true

        panel.orderOut(nil)
        searchViewController.reset()

        let applicationToRestore = previousApplication
        previousApplication = nil
        isDismissing = false

        if restoringPreviousApplication {
            applicationToRestore?.activate(options: [])
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide(restoringPreviousApplication: false)
    }

    private func capturePreviousApplication() {
        let current = NSWorkspace.shared.frontmostApplication
        if current?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = current
        }
    }

    private func positionPanelOnActiveScreen() {
        guard let screen = PanelPositioning.activeScreen() else { return }
        panel.setFrame(
            PanelPositioning.spotlightFrame(
                size: NSSize(width: Self.panelWidth, height: panelHeight),
                in: screen.visibleFrame
            ),
            display: false
        )
    }

    private func resizePanel(to height: CGFloat) {
        panelHeight = height
        guard hasCreatedPanel else { return }
        guard panel.isVisible else { return }
        positionPanelOnActiveScreen()
    }

    private func open(_ url: URL) {
        hide(restoringPreviousApplication: false)
        NSWorkspace.shared.open(url)
    }

    private func openIndexManager() {
        hideForIndexManager()
        onOpenIndexManager?()
    }

    private func hideForIndexManager() {
        guard panel.isVisible, !isDismissing else { return }
        isDismissing = true
        panel.orderOut(nil)
        searchViewController.reset()
        isDismissing = false
    }

    private func makePanel() -> SearchPanel {
        let panelSize = NSSize(width: Self.panelWidth, height: panelHeight)
        let panel = SearchPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        panel.contentViewController = searchViewController
        panel.delegate = self
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        panel.animationBehavior = .utilityWindow
        panel.onOpenIndexManager = { [weak self] in
            self?.openIndexManager()
        }
        hasCreatedPanel = true

        return panel
    }
}

private final class SearchPanel: NSPanel {
    var onOpenIndexManager: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "i" {
            onOpenIndexManager?()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}
