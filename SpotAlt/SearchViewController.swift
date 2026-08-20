import AppKit

final class SearchViewController: NSViewController {
    var onDismiss: (() -> Void)?
    var onOpenFile: ((URL) -> Void)?
    var onOpenIndexManager: (() -> Void)?
    var onPreferredHeightChange: ((CGFloat) -> Void)?

    private let filenameIndex: FilenameIndex
    private let locationStore: SearchLocationStore
    private let searchField = LauncherTextField()
    private let resultsTable = NSTableView()
    private let scrollView = NSScrollView()
    private let separator = NSBox()
    private let messageContainer = NSView()
    private let messageLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let primaryActionButton = NSButton()
    private let indexingLabel = NSTextField(labelWithString: "")

    private var results: [IndexedFile] = []
    private var indexSnapshot = FilenameIndexSnapshot(
        indexedFileCount: 0,
        scannedFileCount: 0,
        isIndexing: false
    )
    private var observerToken: UUID?
    private var currentPreferredHeight: CGFloat = 68
    private var scrollBottomToPanelConstraint: NSLayoutConstraint?
    private var scrollBottomToStatusConstraint: NSLayoutConstraint?

    init(filenameIndex: FilenameIndex, locationStore: SearchLocationStore) {
        self.filenameIndex = filenameIndex
        self.locationStore = locationStore
        super.init(nibName: nil, bundle: nil)

        observerToken = filenameIndex.observe { [weak self] snapshot in
            self?.indexSnapshot = snapshot
            self?.refreshResults()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observerToken {
            filenameIndex.removeObserver(observerToken)
        }
    }

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
        searchField.placeholderString = "Search indexed files"
        searchField.font = .systemFont(ofSize: 23, weight: .regular)
        searchField.textColor = .labelColor
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.lineBreakMode = .byTruncatingTail
        searchField.delegate = self
        searchField.onEscape = { [weak self] in self?.onDismiss?() }
        searchField.onMoveSelection = { [weak self] offset in
            self?.moveSelection(by: offset)
        }
        searchField.onSubmit = { [weak self] in self?.openSelectedResult() }
        searchField.onOpenIndexManager = { [weak self] in
            self?.onOpenIndexManager?()
        }

        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        tableColumn.resizingMask = .autoresizingMask
        resultsTable.addTableColumn(tableColumn)
        resultsTable.headerView = nil
        resultsTable.rowHeight = 52
        resultsTable.intercellSpacing = NSSize(width: 0, height: 2)
        resultsTable.backgroundColor = .clear
        resultsTable.selectionHighlightStyle = .regular
        resultsTable.dataSource = self
        resultsTable.delegate = self
        resultsTable.target = self
        resultsTable.doubleAction = #selector(openSelectedResult)

        scrollView.documentView = resultsTable
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        messageContainer.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        messageLabel.alignment = .center
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.maximumNumberOfLines = 2
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        primaryActionButton.title = "Open Index Manager"
        primaryActionButton.bezelStyle = .rounded
        primaryActionButton.keyEquivalent = "\r"
        primaryActionButton.target = self
        primaryActionButton.action = #selector(openIndexManager)
        primaryActionButton.translatesAutoresizingMaskIntoConstraints = false

        indexingLabel.font = .systemFont(ofSize: 12)
        indexingLabel.textColor = .secondaryLabelColor
        indexingLabel.alignment = .center
        indexingLabel.translatesAutoresizingMaskIntoConstraints = false

        effectView.addSubview(searchIcon)
        effectView.addSubview(searchField)
        effectView.addSubview(separator)
        effectView.addSubview(scrollView)
        effectView.addSubview(messageContainer)
        effectView.addSubview(indexingLabel)
        messageContainer.addSubview(messageLabel)
        messageContainer.addSubview(detailLabel)
        messageContainer.addSubview(primaryActionButton)

        scrollBottomToPanelConstraint = scrollView.bottomAnchor.constraint(
            equalTo: effectView.bottomAnchor
        )
        scrollBottomToStatusConstraint = scrollView.bottomAnchor.constraint(
            equalTo: indexingLabel.topAnchor
        )
        scrollBottomToPanelConstraint?.isActive = true

        NSLayoutConstraint.activate([
            searchIcon.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 21),
            searchIcon.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 20),
            searchIcon.widthAnchor.constraint(equalToConstant: 27),
            searchIcon.heightAnchor.constraint(equalToConstant: 27),

            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -24),
            searchField.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 16),
            searchField.heightAnchor.constraint(equalToConstant: 36),

            separator.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 67),
            separator.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -8),

            messageContainer.topAnchor.constraint(equalTo: separator.bottomAnchor),
            messageContainer.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            messageContainer.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            messageContainer.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),

            messageLabel.topAnchor.constraint(equalTo: messageContainer.topAnchor, constant: 20),
            messageLabel.leadingAnchor.constraint(equalTo: messageContainer.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: messageContainer.trailingAnchor, constant: -24),

            detailLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 5),
            detailLabel.leadingAnchor.constraint(equalTo: messageContainer.leadingAnchor, constant: 24),
            detailLabel.trailingAnchor.constraint(equalTo: messageContainer.trailingAnchor, constant: -24),

            primaryActionButton.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 13),
            primaryActionButton.centerXAnchor.constraint(equalTo: messageContainer.centerXAnchor),

            indexingLabel.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 16),
            indexingLabel.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -16),
            indexingLabel.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -7),
            indexingLabel.heightAnchor.constraint(equalToConstant: 16)
        ])

        view = effectView
        refreshResults()
    }

    func focusSearchField() {
        view.window?.makeFirstResponder(searchField)
    }

    func reset() {
        searchField.stringValue = ""
        results = []
        refreshResults()
    }

    private func refreshResults() {
        guard isViewLoaded else { return }

        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        results = filenameIndex.search(query)
        resultsTable.reloadData()

        let hasLocations = !locationStore.locations.isEmpty
        if !hasLocations {
            showMessage(
                title: "No folders are indexed yet",
                detail: "Add folders before SpotAlt can search your Mac.",
                showsAction: true,
                preferredHeight: 190
            )
            return
        }

        if query.isEmpty {
            scrollView.isHidden = true
            messageContainer.isHidden = true
            separator.isHidden = true
            indexingLabel.isHidden = !indexSnapshot.isIndexing
            if indexSnapshot.isIndexing {
                indexingLabel.stringValue = indexingStatus
                setPreferredHeight(94)
            } else {
                setPreferredHeight(68)
            }
            return
        }

        separator.isHidden = false
        primaryActionButton.isHidden = true

        if results.isEmpty {
            let detail = indexSnapshot.isIndexing
                ? "SpotAlt is still indexing. Results will appear as files are discovered."
                : "Try a different filename or add another search location with ⌘I."
            showMessage(
                title: "No matching files",
                detail: detail,
                showsAction: false,
                preferredHeight: 150
            )
            return
        }

        messageContainer.isHidden = true
        scrollView.isHidden = false
        updateResultsFooter(showsIndexingStatus: indexSnapshot.isIndexing)
        indexingLabel.stringValue = indexingStatus
        let statusHeight: CGFloat = indexSnapshot.isIndexing ? 26 : 0
        let resultListHeight = 12 + min(CGFloat(results.count), 10) * 54
        setPreferredHeight(68 + resultListHeight + statusHeight)

        if resultsTable.selectedRow < 0, !results.isEmpty {
            resultsTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private var indexingStatus: String {
        "Indexing… \(indexSnapshot.scannedFileCount.formatted()) files discovered"
    }

    private func showMessage(
        title: String,
        detail: String,
        showsAction: Bool,
        preferredHeight: CGFloat
    ) {
        separator.isHidden = false
        scrollView.isHidden = true
        messageContainer.isHidden = false
        indexingLabel.isHidden = true
        messageLabel.stringValue = title
        detailLabel.stringValue = detail
        primaryActionButton.isHidden = !showsAction
        setPreferredHeight(preferredHeight)
    }

    private func updateResultsFooter(showsIndexingStatus: Bool) {
        indexingLabel.isHidden = !showsIndexingStatus
        scrollBottomToPanelConstraint?.isActive = !showsIndexingStatus
        scrollBottomToStatusConstraint?.isActive = showsIndexingStatus
    }

    private func setPreferredHeight(_ height: CGFloat) {
        guard currentPreferredHeight != height else { return }
        currentPreferredHeight = height
        onPreferredHeightChange?(height)
    }

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let currentRow = max(resultsTable.selectedRow, 0)
        let newRow = min(max(currentRow + offset, 0), results.count - 1)
        resultsTable.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        resultsTable.scrollRowToVisible(newRow)
    }

    @objc private func openSelectedResult() {
        guard !results.isEmpty else {
            if locationStore.locations.isEmpty {
                onOpenIndexManager?()
            }
            return
        }

        let row = max(resultsTable.selectedRow, 0)
        guard results.indices.contains(row) else { return }
        onOpenFile?(results[row].url)
    }

    @objc private func openIndexManager() {
        onOpenIndexManager?()
    }
}

extension SearchViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        refreshResults()
    }
}

extension SearchViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("SearchResultCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self)
            as? SearchResultCellView ?? SearchResultCellView(identifier: identifier)
        cell.configure(with: results[row])
        return cell
    }
}

private final class SearchResultCellView: NSTableCellView {
    private let fileIcon = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        fileIcon.translatesAutoresizingMaskIntoConstraints = false
        fileIcon.imageScaling = .scaleProportionallyUpOrDown

        nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(fileIcon)
        addSubview(nameLabel)
        addSubview(pathLabel)
        NSLayoutConstraint.activate([
            fileIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            fileIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            fileIcon.widthAnchor.constraint(equalToConstant: 32),
            fileIcon.heightAnchor.constraint(equalToConstant: 32),

            nameLabel.leadingAnchor.constraint(equalTo: fileIcon.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),

            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            pathLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with file: IndexedFile) {
        nameLabel.stringValue = file.name
        pathLabel.stringValue = file.parentPath
        fileIcon.image = NSWorkspace.shared.icon(forFile: file.path)
    }
}

private final class LauncherTextField: NSTextField {
    var onEscape: (() -> Void)?
    var onMoveSelection: ((Int) -> Void)?
    var onSubmit: (() -> Void)?
    var onOpenIndexManager: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "i" {
            onOpenIndexManager?()
            return
        }

        switch event.keyCode {
        case 53:
            onEscape?()
        case 125:
            onMoveSelection?(1)
        case 126:
            onMoveSelection?(-1)
        case 36, 76:
            onSubmit?()
        default:
            super.keyDown(with: event)
        }
    }
}
