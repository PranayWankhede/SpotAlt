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
    private let persistedIndexURL: URL?

    private var records: [IndexedFile] = []
    private var observers: [UUID: Observer] = [:]
    private var locationsObserver: NSObjectProtocol?
    private var rebuildGeneration = 0
    private var scannedFileCount = 0
    private(set) var isIndexing = false

    init(locationStore: SearchLocationStore) {
        self.locationStore = locationStore
        persistedIndexURL = Self.makePersistedIndexURL()
        records = Self.loadPersistedIndex(from: persistedIndexURL)
        records = Self.records(records, containedIn: locationStore.locations)

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
        if let locationsObserver {
            NotificationCenter.default.removeObserver(locationsObserver)
        }
    }

    var indexedFileCount: Int {
        records.count
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

        guard !locations.isEmpty else {
            records = []
            isIndexing = false
            persist([])
            notifyObservers()
            return
        }

        isIndexing = true
        notifyObservers()

        workerQueue.async { [weak self] in
            guard let self else { return }

            let scannedRecords = Self.scan(locations: locations) { partialRecords in
                DispatchQueue.main.async { [weak self] in
                    guard let self, generation == self.rebuildGeneration else { return }
                    self.records = partialRecords
                    self.scannedFileCount = partialRecords.count
                    self.notifyObservers()
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.rebuildGeneration else { return }
                self.records = scannedRecords
                self.scannedFileCount = scannedRecords.count
                self.isIndexing = false
                self.persist(scannedRecords)
                self.notifyObservers()
            }
        }
    }

    func search(_ query: String, limit: Int = 10) -> [IndexedFile] {
        let normalizedQuery = Self.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        return records.compactMap { record -> (IndexedFile, Int)? in
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
        progress: (([IndexedFile]) -> Void)? = nil
    ) -> [IndexedFile] {
        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .contentModificationDateKey
        ]
        var files: [IndexedFile] = []
        var indexedPaths: Set<String> = []

        for location in locations {
            guard let enumerator = FileManager.default.enumerator(
                at: location,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys))

                if values?.isDirectory == true {
                    if ignoredDirectoryNames.contains(fileURL.lastPathComponent) {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                guard values?.isRegularFile == true else { continue }
                guard indexedPaths.insert(fileURL.path).inserted else { continue }
                files.append(
                    IndexedFile(
                        name: fileURL.lastPathComponent,
                        path: fileURL.path,
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
            indexedFileCount: records.count,
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

    private func persist(_ records: [IndexedFile]) {
        guard let persistedIndexURL else { return }
        workerQueue.async {
            guard let data = try? JSONEncoder().encode(records) else { return }
            try? data.write(to: persistedIndexURL, options: .atomic)
        }
    }

    private static func makePersistedIndexURL() -> URL? {
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
        return directory.appendingPathComponent("filename-index.json")
    }

    private static func loadPersistedIndex(from url: URL?) -> [IndexedFile] {
        guard let url,
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([IndexedFile].self, from: data)
        else { return [] }

        return records
    }

    private static func records(
        _ records: [IndexedFile],
        containedIn locations: [URL]
    ) -> [IndexedFile] {
        let rootPaths = locations.map { $0.standardizedFileURL.path + "/" }
        return records.filter { record in
            rootPaths.contains { record.path.hasPrefix($0) }
        }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
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
