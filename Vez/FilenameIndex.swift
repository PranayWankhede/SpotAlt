import Foundation

struct IndexedFile: Codable, Hashable {
    let name: String
    let path: String
    let modifiedAt: Date?

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var parentPath: String {
        url.deletingLastPathComponent().path
    }
}

struct FilenameIndexSnapshot {
    let indexedFileCount: Int
    let scannedFileCount: Int
    let isIndexing: Bool
}

final class FilenameIndex {
    typealias Observer = (FilenameIndexSnapshot) -> Void

    private static let ignoredDirectoryNames: Set<String> = [
        ".git", ".hg", ".svn", ".build", "DerivedData", "node_modules", "Pods"
    ]

    private let locationStore: SearchLocationStore
    private let workerQueue = DispatchQueue(
        label: "com.vez.filename-index",
        qos: .utility
    )
    private let indexStore: SQLiteIndexStore?
    private let legacyJSONURL: URL?
    private let folderWatcher: FolderWatching
    private let excludedPaths: Set<String>

    private var transientRecords: [IndexedFile] = []
    private var indexedFileCountValue = 0
    private var observers: [UUID: Observer] = [:]
    private var locationsObserver: NSObjectProtocol?
    private var rebuildGeneration = 0
    private var scannedFileCount = 0
    private var rebuildInProgress = false
    private var pendingIncrementalUpdateCount = 0
    private(set) var isIndexing = false

    init(
        locationStore: SearchLocationStore,
        databaseURL: URL? = nil,
        legacyJSONURL: URL? = nil,
        folderWatcher: FolderWatching = FSEventsFolderWatcher()
    ) {
        self.locationStore = locationStore
        self.folderWatcher = folderWatcher
        let applicationSupportDirectory = Self.makeApplicationSupportDirectory()
        let resolvedDatabaseURL = databaseURL
            ?? applicationSupportDirectory?.appendingPathComponent("index.sqlite")
        let resolvedLegacyJSONURL = legacyJSONURL
            ?? applicationSupportDirectory?.appendingPathComponent("filename-index.json")
        self.legacyJSONURL = resolvedLegacyJSONURL
        excludedPaths = Set(
            [resolvedDatabaseURL, resolvedLegacyJSONURL]
                .compactMap { $0?.deletingLastPathComponent().standardizedFileURL.path }
        )
        indexStore = resolvedDatabaseURL.flatMap { try? SQLiteIndexStore(databaseURL: $0) }

        folderWatcher.onEvents = { [weak self] events in
            DispatchQueue.main.async {
                self?.handleFileSystemEvents(events)
            }
        }

        migrateLegacyJSONIfNeeded()
        try? indexStore?.synchronizeRoots(locationStore.locations)
        indexedFileCountValue = (try? indexStore?.fileCount()) ?? 0

        locationsObserver = NotificationCenter.default.addObserver(
            forName: .vezSearchLocationsDidChange,
            object: locationStore,
            queue: .main
        ) { [weak self] _ in
            self?.rebuild()
        }

        rebuild()
    }

    deinit {
        folderWatcher.stop()
        if let locationsObserver {
            NotificationCenter.default.removeObserver(locationsObserver)
        }
    }

    var indexedFileCount: Int {
        indexedFileCountValue
    }

    @discardableResult
    func observe(_ observer: @escaping Observer) -> UUID {
        let token = UUID()
        observers[token] = observer
        observer(snapshot)
        return token
    }

    func removeObserver(_ token: UUID) {
        observers.removeValue(forKey: token)
    }

    func rebuild() {
        rebuildGeneration += 1
        let generation = rebuildGeneration
        let locations = locationStore.locations
        scannedFileCount = 0
        pendingIncrementalUpdateCount = 0
        folderWatcher.start(watching: locations)

        guard !locations.isEmpty else {
            transientRecords = []
            try? indexStore?.synchronizeRoots([])
            indexedFileCountValue = 0
            rebuildInProgress = false
            updateIndexingState()
            notifyObservers()
            return
        }

        try? indexStore?.synchronizeRoots(locations)
        indexedFileCountValue = (try? indexStore?.fileCount()) ?? 0
        transientRecords = []
        rebuildInProgress = true
        updateIndexingState()
        notifyObservers()

        workerQueue.async { [weak self] in
            guard let self else { return }

            let scannedRecords = Self.scan(
                locations: locations,
                excludingPaths: self.excludedPaths
            ) { partialRecords in
                DispatchQueue.main.async { [weak self] in
                    guard let self, generation == self.rebuildGeneration else { return }
                    self.transientRecords = partialRecords
                    self.scannedFileCount = partialRecords.count
                    self.notifyObservers()
                }
            }

            let shouldPersist = DispatchQueue.main.sync {
                generation == self.rebuildGeneration
            }
            guard shouldPersist else { return }

            var persistedCount: Int?
            if let indexStore = self.indexStore {
                do {
                    try indexStore.replaceIndex(with: scannedRecords, roots: locations)
                    persistedCount = try indexStore.fileCount()
                } catch {
                    persistedCount = nil
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.rebuildGeneration else { return }
                self.scannedFileCount = scannedRecords.count
                self.indexedFileCountValue = persistedCount ?? scannedRecords.count
                self.transientRecords = persistedCount == nil ? scannedRecords : []
                self.rebuildInProgress = false
                self.updateIndexingState()
                self.notifyObservers()
            }
        }
    }

    func search(_ query: String, limit: Int = 10) -> [IndexedFile] {
        let normalizedQuery = Self.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let persistedCandidates = (try? indexStore?.searchCandidates(for: normalizedQuery)) ?? []
        let candidates = Self.deduplicated(persistedCandidates + transientRecords)

        return candidates.compactMap { record -> (IndexedFile, Int)? in
            guard let score = Self.matchScore(query: normalizedQuery, file: record) else {
                return nil
            }
            return (record, score)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 {
                return lhs.1 > rhs.1
            }

            let lhsDate = lhs.0.modifiedAt ?? .distantPast
            let rhsDate = rhs.0.modifiedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }

            return lhs.0.name.localizedStandardCompare(rhs.0.name) == .orderedAscending
        }
        .prefix(limit)
        .map(\.0)
    }

    static func scan(
        locations: [URL],
        excludingPaths: Set<String> = [],
        progress: (([IndexedFile]) -> Void)? = nil
    ) -> [IndexedFile] {
        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey
        ]
        var files: [IndexedFile] = []
        var indexedPaths: Set<String> = []

        for requestedLocation in locations {
            let location = canonicalURL(requestedLocation)
            guard !isExcluded(location.path, excludedPaths: excludingPaths) else {
                continue
            }
            guard let enumerator = FileManager.default.enumerator(
                at: location,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let fileURL as URL in enumerator {
                let sourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
                if sourceValues?.isSymbolicLink == true {
                    if sourceValues?.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                let canonicalFileURL = canonicalURL(fileURL)
                let values = try? canonicalFileURL.resourceValues(forKeys: Set(resourceKeys))

                if isExcluded(canonicalFileURL.path, excludedPaths: excludingPaths) {
                    if values?.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                if values?.isDirectory == true {
                    if values?.isSymbolicLink == true
                        || ignoredDirectoryNames.contains(canonicalFileURL.lastPathComponent) {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                guard values?.isRegularFile == true else { continue }
                guard values?.isSymbolicLink != true else { continue }
                guard indexedPaths.insert(canonicalFileURL.path).inserted else { continue }
                files.append(
                    IndexedFile(
                        name: canonicalFileURL.lastPathComponent,
                        path: canonicalFileURL.path,
                        modifiedAt: values?.contentModificationDate
                    )
                )

                if files.count.isMultiple(of: 250) {
                    progress?(files)
                }
            }
        }

        progress?(files)
        return files
    }

    private func handleFileSystemEvents(_ events: [FileSystemEvent]) {
        guard !events.isEmpty, let indexStore else { return }

        let generation = rebuildGeneration
        let locations = locationStore.locations
        guard !locations.isEmpty else { return }

        pendingIncrementalUpdateCount += 1
        updateIndexingState()
        notifyObservers()

        workerQueue.async { [weak self] in
            guard let self else { return }

            let updatedCount = try? Self.applyFileSystemEvents(
                events,
                roots: locations,
                excludingPaths: self.excludedPaths,
                to: indexStore
            )

            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.rebuildGeneration else { return }
                self.pendingIncrementalUpdateCount = max(
                    0,
                    self.pendingIncrementalUpdateCount - 1
                )
                if let updatedCount {
                    self.indexedFileCountValue = updatedCount
                }
                self.updateIndexingState()
                self.notifyObservers()
            }
        }
    }

    static func applyFileSystemEvents(
        _ events: [FileSystemEvent],
        roots: [URL],
        excludingPaths: Set<String>,
        to indexStore: SQLiteIndexStore
    ) throws -> Int {
        let standardizedRoots = roots
            .map(canonicalURL)
            .sorted { $0.path.count > $1.path.count }
        var directoryPaths: Set<String> = []
        var filePaths: Set<String> = []

        for event in events {
            let sourceURL = URL(fileURLWithPath: event.path).standardizedFileURL
            let path = canonicalURLPreservingLastComponent(sourceURL).path
            guard !isExcluded(path, excludedPaths: excludingPaths),
                  let root = root(containing: path, roots: standardizedRoots)
            else { continue }

            if event.requiresFullRescan {
                directoryPaths.insert(root.path)
                continue
            }

            if (try? sourceURL.resourceValues(
                forKeys: [.isSymbolicLinkKey]
            ).isSymbolicLink) == true {
                filePaths.insert(path)
                continue
            }

            var isDirectory = ObjCBool(event.isDirectory)
            let exists = FileManager.default.fileExists(
                atPath: path,
                isDirectory: &isDirectory
            )
            if event.isDirectory || (exists && isDirectory.boolValue) {
                directoryPaths.insert(path)
            } else {
                filePaths.insert(path)
            }
        }

        let compactDirectoryPaths = compactSubtrees(directoryPaths)
        filePaths = filePaths.filter { path in
            !compactDirectoryPaths.contains(where: {
                contains(path: path, in: $0)
            })
        }

        var upsertsByPath: [String: IndexedFile] = [:]
        for path in compactDirectoryPaths {
            guard let root = root(containing: path, roots: standardizedRoots) else {
                continue
            }
            let directoryURL = URL(fileURLWithPath: path, isDirectory: true)
            guard isIndexableDirectory(directoryURL, within: root) else { continue }

            for file in scan(
                locations: [directoryURL],
                excludingPaths: excludingPaths
            ) {
                upsertsByPath[file.path] = file
            }
        }

        for path in filePaths {
            guard let root = root(containing: path, roots: standardizedRoots),
                  let file = indexedFile(at: URL(fileURLWithPath: path), within: root)
            else { continue }
            upsertsByPath[file.path] = file
        }

        return try indexStore.applyChanges(
            upserting: Array(upsertsByPath.values),
            deletingPaths: filePaths,
            deletingSubtrees: Set(compactDirectoryPaths)
        )
    }

    private func updateIndexingState() {
        isIndexing = rebuildInProgress || pendingIncrementalUpdateCount > 0
    }

    private static func root(containing path: String, roots: [URL]) -> URL? {
        roots.first { contains(path: path, in: $0.path) }
    }

    private static func compactSubtrees(_ paths: Set<String>) -> [String] {
        let sortedPaths = paths.sorted {
            if $0.count != $1.count {
                return $0.count < $1.count
            }
            return $0 < $1
        }
        var compactPaths: [String] = []

        for path in sortedPaths where !compactPaths.contains(where: {
            contains(path: path, in: $0)
        }) {
            compactPaths.append(path)
        }

        return compactPaths
    }

    private static func indexedFile(at url: URL, within root: URL) -> IndexedFile? {
        let sourceURL = url.standardizedFileURL
        guard (try? sourceURL.resourceValues(
            forKeys: [.isSymbolicLinkKey]
        ).isSymbolicLink) != true else { return nil }
        let standardizedURL = canonicalURL(url)
        guard contains(path: standardizedURL.path, in: root.path),
              !standardizedURL.lastPathComponent.hasPrefix("."),
              isIndexableDirectory(
                  standardizedURL.deletingLastPathComponent(),
                  within: root
              )
        else { return nil }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isHiddenKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey
        ]
        guard let values = try? standardizedURL.resourceValues(forKeys: keys),
              values.isRegularFile == true,
              values.isHidden != true,
              values.isSymbolicLink != true
        else { return nil }

        return IndexedFile(
            name: standardizedURL.lastPathComponent,
            path: standardizedURL.path,
            modifiedAt: values.contentModificationDate
        )
    }

    private static func isIndexableDirectory(_ url: URL, within root: URL) -> Bool {
        let standardizedRoot = canonicalURL(root)
        let standardizedURL = canonicalURL(url)
        let rootComponents = standardizedRoot.pathComponents
        let candidateComponents = standardizedURL.pathComponents

        guard contains(path: standardizedURL.path, in: standardizedRoot.path),
              candidateComponents.starts(with: rootComponents)
        else { return false }

        let relativeComponents = candidateComponents.dropFirst(rootComponents.count)
        guard !relativeComponents.contains(where: {
            $0.hasPrefix(".") || ignoredDirectoryNames.contains($0)
        }) else { return false }

        var directory = standardizedRoot
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isHiddenKey,
            .isPackageKey,
            .isSymbolicLinkKey
        ]

        for component in relativeComponents {
            directory.appendPathComponent(component, isDirectory: true)
            guard let values = try? directory.resourceValues(forKeys: keys),
                  values.isDirectory == true,
                  values.isHidden != true,
                  values.isPackage != true,
                  values.isSymbolicLink != true
            else { return false }
        }

        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(
            atPath: standardizedURL.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    private static func isExcluded(
        _ path: String,
        excludedPaths: Set<String>
    ) -> Bool {
        excludedPaths.contains { contains(path: path, in: $0) }
    }

    private static func contains(path: String, in rootPath: String) -> Bool {
        path == rootPath
            || (rootPath == "/" ? path.hasPrefix("/") : path.hasPrefix(rootPath + "/"))
    }

    private static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func canonicalURLPreservingLastComponent(_ url: URL) -> URL {
        let standardizedURL = url.standardizedFileURL
        return standardizedURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(standardizedURL.lastPathComponent)
    }

    static func matchScore(query: String, file: IndexedFile) -> Int? {
        let query = normalize(query)
        let name = normalize(file.name)
        let path = normalize(file.parentPath)

        if name == query {
            return 1_000
        }
        if name.hasPrefix(query) {
            return 900 - min(name.count - query.count, 100)
        }
        if let range = name.range(of: query) {
            return 800 - min(name.distance(from: name.startIndex, to: range.lowerBound), 100)
        }

        let terms = query.split(separator: " ").map(String.init)
        if terms.count > 1, terms.allSatisfy({ name.contains($0) || path.contains($0) }) {
            return 700
        }
        if isSubsequence(query, of: name) {
            return 600 - min(name.count - query.count, 100)
        }
        if path.contains(query) {
            return 400
        }

        return nil
    }

    private var snapshot: FilenameIndexSnapshot {
        FilenameIndexSnapshot(
            indexedFileCount: indexedFileCountValue,
            scannedFileCount: scannedFileCount,
            isIndexing: isIndexing
        )
    }

    private func notifyObservers() {
        let currentSnapshot = snapshot
        for observer in observers.values {
            observer(currentSnapshot)
        }
    }

    private static func makeApplicationSupportDirectory() -> URL? {
        guard let applicationSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }

        let directory = applicationSupport.appendingPathComponent("Vez", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func migrateLegacyJSONIfNeeded() {
        guard let indexStore,
              (try? indexStore.fileCount()) == 0,
              let legacyJSONURL,
              let data = try? Data(contentsOf: legacyJSONURL),
              let records = try? JSONDecoder().decode([IndexedFile].self, from: data)
        else { return }

        let activeRecords = Self.records(records, containedIn: locationStore.locations)
        guard (try? indexStore.replaceIndex(
            with: activeRecords,
            roots: locationStore.locations
        )) != nil else { return }

        try? FileManager.default.removeItem(at: legacyJSONURL)
    }

    private static func records(
        _ records: [IndexedFile],
        containedIn locations: [URL]
    ) -> [IndexedFile] {
        let rootPaths = locations.map { canonicalURL($0).path + "/" }
        return records.filter { record in
            rootPaths.contains { record.path.hasPrefix($0) }
        }
    }

    private static func deduplicated(_ records: [IndexedFile]) -> [IndexedFile] {
        var paths: Set<String> = []
        return records.filter { paths.insert($0.path).inserted }
    }

    private static func normalize(_ value: String) -> String {
        SearchTextNormalizer.normalize(value)
    }

    private static func isSubsequence(_ query: String, of candidate: String) -> Bool {
        var queryIndex = query.startIndex

        for character in candidate where queryIndex < query.endIndex {
            if character == query[queryIndex] {
                query.formIndex(after: &queryIndex)
            }
        }

        return queryIndex == query.endIndex
    }
}
