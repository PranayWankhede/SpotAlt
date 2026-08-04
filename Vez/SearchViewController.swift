import AppKit

final class SearchViewController: NSViewController {
    var onDismiss: (() -> Void)?

    private let searchField = LauncherTextField()

    override func loadView() {
        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 0.5
        effectView.layer?.borderColor = NSColor.separatorColor
            .withAlphaComponent(0.35)
            .cgColor

        let searchIcon = NSImageView()
        searchIcon.image = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: nil
        )
        searchIcon.contentTintColor = .secondaryLabelColor
        searchIcon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 23,
            weight: .regular
        )
        searchIcon.translatesAutoresizingMaskIntoConstraints = false

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search files with Vez"
        searchField.font = .systemFont(ofSize: 23, weight: .regular)
        searchField.textColor = .labelColor
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.lineBreakMode = .byTruncatingTail
        searchField.onEscape = { [weak self] in
            self?.onDismiss?()
        }

        effectView.addSubview(searchIcon)
        effectView.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchIcon.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 21),
            searchIcon.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 27),
            searchIcon.heightAnchor.constraint(equalToConstant: 27),

            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -24),
            searchField.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 36)
        ])

        view = effectView
    }

    func focusSearchField() {
        view.window?.makeFirstResponder(searchField)
    }

    func reset() {
        searchField.stringValue = ""
    }
}

private final class LauncherTextField: NSTextField {
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }

        super.keyDown(with: event)
    }
}
