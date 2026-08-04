import AppKit

final class SearchPanelController: NSObject, NSWindowDelegate {
    private static let panelSize = NSSize(width: 680, height: 68)

    private let searchViewController = SearchViewController()
    private lazy var panel: SearchPanel = makePanel()
    private var previousApplication: NSRunningApplication?
    private var isDismissing = false

    override init() {
        super.init()
        searchViewController.onDismiss = { [weak self] in
            self?.hide(restoringPreviousApplication: true)
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
                size: Self.panelSize,
                in: screen.visibleFrame
            ),
            display: false
        )
    }

    private func makePanel() -> SearchPanel {
        let panel = SearchPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
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

        return panel
    }
}

private final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
