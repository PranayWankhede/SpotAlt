import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onReturnToSearch: (() -> Void)?

    convenience init() {
        let contentViewController = NSViewController()
        let contentView = NSView()

        let titleLabel = NSTextField(labelWithString: "SpotAlt Settings")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let shortcutLabel = NSTextField(labelWithString: "Global shortcut: Option-Space")
        shortcutLabel.font = .systemFont(ofSize: 14)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(shortcutLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            shortcutLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            shortcutLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor)
        ])

        contentViewController.view = contentView

        let window = NSWindow(contentViewController: contentViewController)
        window.title = "SpotAlt Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 420, height: 180))
        window.isReleasedWhenClosed = false

        self.init(window: window)
        window.delegate = self
    }

    func show() {
        guard let window else { return }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let returnToSearch = onReturnToSearch
        DispatchQueue.main.async {
            returnToSearch?()
        }
    }
}
