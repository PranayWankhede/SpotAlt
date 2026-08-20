import AppKit

final class IndexManagerWindowController: NSWindowController, NSWindowDelegate {
    var onReturnToSearch: (() -> Void)?

    private let locationStore: SearchLocationStore
    private let filenameIndex: FilenameIndex
    private let locationsStack = NSStackView()
    private let emptyStateLabel = NSTextField(labelWithString: "")
    private let fileCountLabel = NSTextField(labelWithString: "0")
    private let locationCountLabel = NSTextField(labelWithString: "0")
    private let statusLabel = NSTextField(labelWithString: "Idle")
    private let progressIndicator = NSProgressIndicator()
    private let addHomeButton = NSButton()

    private var indexObserverToken: UUID?
    private var locationsObserver: NSObjectProtocol?
    private var returnsToSearchWhenClosed = false

    init(locationStore: SearchLocationStore, filenameIndex: FilenameIndex) {
        self.locationStore = locationStore
        self.filenameIndex = filenameIndex
        super.init(window: nil)
        window = makeWindow()
        window?.delegate = self

        indexObserverToken = filenameIndex.observe { [weak self] snapshot in
            self?.update(snapshot: snapshot)
        }
        locationsObserver = NotificationCenter.default.addObserver(
            forName: .vezSearchLocationsDidChange,
            object: locationStore,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildLocationsList()
        }

        rebuildLocationsList()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let indexObserverToken {
            filenameIndex.removeObserver(indexObserverToken)
        }
        if let locationsObserver {
            NotificationCenter.default.removeObserver(locationsObserver)
        }
    }

    func show(returnToSearchWhenClosed: Bool = true) {
        guard let window else { return }
        returnsToSearchWhenClosed = returnToSearchWhenClosed
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard returnsToSearchWhenClosed else { return }
        returnsToSearchWhenClosed = false
        let returnToSearch = onReturnToSearch
        DispatchQueue.main.async {
            returnToSearch?()
        }
    }

    private func makeWindow() -> NSWindow {
        let contentViewController = NSViewController()
        let contentView = NSView()

        let titleLabel = NSTextField(labelWithString: "SpotAlt Index")
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(
            labelWithString: "Choose the folders SpotAlt can search. Files remain on this Mac."
        )
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let addFolderButton = NSButton(
            title: "Add Folder…",
            target: self,
            action: #selector(addFolder)
        )
        addFolderButton.bezelStyle = .rounded
        addFolderButton.keyEquivalent = "o"
        addFolderButton.keyEquivalentModifierMask = [.command]
        addFolderButton.translatesAutoresizingMaskIntoConstraints = false

        let fileStat = makeStatCard(valueLabel: fileCountLabel, caption: "INDEXED FILES")
        let locationStat = makeStatCard(valueLabel: locationCountLabel, caption: "LOCATIONS")
        let statusStat = makeStatCard(valueLabel: statusLabel, caption: "STATUS")

        let statsStack = NSStackView(views: [fileStat, locationStat, statusStat])
        statsStack.orientation = .horizontal
        statsStack.distribution = .fillEqually
        statsStack.spacing = 12
        statsStack.translatesAutoresizingMaskIntoConstraints = false

        let locationsTitle = NSTextField(labelWithString: "Search Locations")
        locationsTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        locationsTitle.translatesAutoresizingMaskIntoConstraints = false

        locationsStack.orientation = .vertical
        locationsStack.alignment = .width
        locationsStack.spacing = 8
        locationsStack.translatesAutoresizingMaskIntoConstraints = false

        emptyStateLabel.stringValue = "No folders added yet. Add your Home folder or choose another folder."
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.alignment = .center
        emptyStateLabel.maximumNumberOfLines = 2
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false

        addHomeButton.title = "Search My Home Folder…"
        addHomeButton.target = self
        addHomeButton.action = #selector(addHomeFolder)
        addHomeButton.bezelStyle = .rounded
        addHomeButton.translatesAutoresizingMaskIntoConstraints = false

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        let footerLabel = NSTextField(
            labelWithString: "SpotAlt indexes filenames and paths recursively. Hidden files and common build folders are skipped."
        )
        footerLabel.font = .systemFont(ofSize: 11)
        footerLabel.textColor = .tertiaryLabelColor
        footerLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(addFolderButton)
        contentView.addSubview(statsStack)
        contentView.addSubview(locationsTitle)
        contentView.addSubview(locationsStack)
        contentView.addSubview(emptyStateLabel)
        contentView.addSubview(addHomeButton)
        contentView.addSubview(progressIndicator)
        contentView.addSubview(footerLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            addFolderButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            addFolderButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            statsStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            statsStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            statsStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            statsStack.heightAnchor.constraint(equalToConstant: 92),

            locationsTitle.topAnchor.constraint(equalTo: statsStack.bottomAnchor, constant: 26),
            locationsTitle.leadingAnchor.constraint(equalTo: statsStack.leadingAnchor),

            progressIndicator.leadingAnchor.constraint(equalTo: locationsTitle.trailingAnchor, constant: 10),
            progressIndicator.centerYAnchor.constraint(equalTo: locationsTitle.centerYAnchor),

            locationsStack.topAnchor.constraint(equalTo: locationsTitle.bottomAnchor, constant: 12),
            locationsStack.leadingAnchor.constraint(equalTo: statsStack.leadingAnchor),
            locationsStack.trailingAnchor.constraint(equalTo: statsStack.trailingAnchor),

            emptyStateLabel.topAnchor.constraint(equalTo: locationsTitle.bottomAnchor, constant: 44),
            emptyStateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 60),
            emptyStateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -60),

            addHomeButton.topAnchor.constraint(equalTo: emptyStateLabel.bottomAnchor, constant: 14),
            addHomeButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            footerLabel.leadingAnchor.constraint(equalTo: statsStack.leadingAnchor),
            footerLabel.trailingAnchor.constraint(equalTo: statsStack.trailingAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22)
        ])

        contentViewController.view = contentView

        let window = NSWindow(contentViewController: contentViewController)
        window.title = "SpotAlt Index Manager"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 720, height: 470))
        window.isReleasedWhenClosed = false
        return window
    }

    private func makeStatCard(
        valueLabel: NSTextField,
        caption: String
    ) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 10

        valueLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        valueLabel.alignment = .center
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        let captionLabel = NSTextField(labelWithString: caption)
        captionLabel.font = .systemFont(ofSize: 10, weight: .medium)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.alignment = .center
        captionLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(valueLabel)
        card.addSubview(captionLabel)
        NSLayoutConstraint.activate([
            valueLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            valueLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -8),

            captionLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 5),
            captionLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor)
        ])
        return card
    }

    private func rebuildLocationsList() {
        for view in locationsStack.arrangedSubviews {
            locationsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let locations = locationStore.locations
        emptyStateLabel.isHidden = !locations.isEmpty
        addHomeButton.isHidden = !locations.isEmpty

        for location in locations {
            locationsStack.addArrangedSubview(makeLocationRow(for: location))
        }

        locationCountLabel.stringValue = locations.count.formatted()
    }

    private func makeLocationRow(for url: URL) -> NSView {
        let row = NSView()
        row.wantsLayer = true
        row.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        row.layer?.cornerRadius = 8

        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: url.path))
        icon.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: url.lastPathComponent)
        nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let pathLabel = NSTextField(labelWithString: url.path)
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        let removeButton = LocationButton(title: "Remove", target: self, action: #selector(removeLocation(_:)))
        removeButton.locationURL = url
        removeButton.bezelStyle = .inline
        removeButton.contentTintColor = .systemRed
        removeButton.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(icon)
        row.addSubview(nameLabel)
        row.addSubview(pathLabel)
        row.addSubview(removeButton)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 62),
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),

            nameLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 11),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -12),

            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -12),
            pathLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),

            removeButton.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            removeButton.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func update(snapshot: FilenameIndexSnapshot) {
        fileCountLabel.stringValue = snapshot.indexedFileCount.formatted()
        if locationStore.locations.isEmpty {
            statusLabel.stringValue = "Not configured"
        } else {
            statusLabel.stringValue = snapshot.isIndexing ? "Indexing" : "Up to date"
        }

        if snapshot.isIndexing {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
    }

    @objc private func addFolder() {
        presentFolderPicker(startingAt: nil)
    }

    @objc private func addHomeFolder() {
        presentFolderPicker(startingAt: FileManager.default.homeDirectoryForCurrentUser)
    }

    private func presentFolderPicker(startingAt directory: URL?) {
        guard let window else { return }

        let panel = NSOpenPanel()
        panel.title = "Choose folders for SpotAlt to index"
        panel.prompt = "Add"
        panel.message = "SpotAlt will recursively index filenames in the selected folders."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.directoryURL = directory

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }

            do {
                try self.locationStore.add(panel.urls)
            } catch {
                self.presentEnrollmentError(error)
            }
        }
    }

    private func presentEnrollmentError(_ error: Error) {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "SpotAlt could not add that folder"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    @objc private func removeLocation(_ sender: LocationButton) {
        guard let url = sender.locationURL else { return }
        locationStore.remove(url)
    }
}

private final class LocationButton: NSButton {
    var locationURL: URL?
}
