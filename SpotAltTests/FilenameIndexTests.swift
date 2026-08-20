import Foundation
import XCTest
@testable import SpotAlt

final class FilenameIndexTests: XCTestCase {
    func testScanRecursivelyIndexesFilesAndSkipsCommonNoise() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("Projects/SpotAlt", isDirectory: true)
        let ignored = root.appendingPathComponent("node_modules/package", isDirectory: true)

        try FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: ignored,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("mvp".utf8).write(to: root.appendingPathComponent("Roadmap.md"))
        try Data("swift".utf8).write(to: nested.appendingPathComponent("SearchIndex.swift"))
        try Data("noise".utf8).write(to: ignored.appendingPathComponent("library.js"))

        let records = FilenameIndex.scan(locations: [root])
        let names = Set(records.map(\.name))

        XCTAssertEqual(names, ["Roadmap.md", "SearchIndex.swift"])
    }

    func testScanDeduplicatesOverlappingLocations() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("file".utf8).write(to: nested.appendingPathComponent("Invoice.pdf"))

        let records = FilenameIndex.scan(locations: [root, nested])

        XCTAssertEqual(records.map(\.name), ["Invoice.pdf"])
    }

    func testFilenameRankingPrefersExactThenPrefixThenSubstring() {
        let exact = file(named: "invoice")
        let prefix = file(named: "invoice-2026.pdf")
        let substring = file(named: "paid-invoice.pdf")

        let exactScore = FilenameIndex.matchScore(query: "invoice", file: exact)
        let prefixScore = FilenameIndex.matchScore(query: "invoice", file: prefix)
        let substringScore = FilenameIndex.matchScore(query: "invoice", file: substring)

        XCTAssertGreaterThan(try XCTUnwrap(exactScore), try XCTUnwrap(prefixScore))
        XCTAssertGreaterThan(try XCTUnwrap(prefixScore), try XCTUnwrap(substringScore))
    }

    func testFilenameRankingSupportsFuzzySubsequence() {
        let result = FilenameIndex.matchScore(
            query: "srchidx",
            file: file(named: "SearchIndex.swift")
        )

        XCTAssertNotNil(result)
    }

    func testFileEventsIncrementallyCreateMoveRenameAndDeleteRecords() throws {
        let fixture = try makeIncrementalFixture()
        defer { fixture.cleanup() }

        let created = fixture.root.appendingPathComponent("Meeting Notes.txt")
        try Data("notes".utf8).write(to: created)
        try applyEvent(for: created, in: fixture)
        XCTAssertEqual(try fixture.store.allFiles().map(\.path), [created.path])

        let archive = fixture.root.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let moved = archive.appendingPathComponent(created.lastPathComponent)
        try FileManager.default.moveItem(at: created, to: moved)
        try applyEvents(
            [
                FileSystemEvent(
                    path: created.path,
                    isDirectory: false,
                    requiresFullRescan: false
                ),
                FileSystemEvent(
                    path: moved.path,
                    isDirectory: false,
                    requiresFullRescan: false
                )
            ],
            in: fixture
        )
        XCTAssertEqual(try fixture.store.allFiles().map(\.path), [moved.path])

        let renamed = archive.appendingPathComponent("Project Notes.txt")
        try FileManager.default.moveItem(at: moved, to: renamed)
        try applyEvents(
            [
                FileSystemEvent(
                    path: moved.path,
                    isDirectory: false,
                    requiresFullRescan: false
                ),
                FileSystemEvent(
                    path: renamed.path,
                    isDirectory: false,
                    requiresFullRescan: false
                )
            ],
            in: fixture
        )
        XCTAssertEqual(try fixture.store.allFiles().map(\.path), [renamed.path])

        try FileManager.default.removeItem(at: renamed)
        try applyEvent(for: renamed, in: fixture)
        XCTAssertTrue(try fixture.store.allFiles().isEmpty)
    }

    func testDirectoryRenameReconcilesEveryFileInTheSubtree() throws {
        let fixture = try makeIncrementalFixture()
        defer { fixture.cleanup() }

        let original = fixture.root.appendingPathComponent("Original", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: original.appendingPathComponent("One.txt"))
        try Data("two".utf8).write(to: original.appendingPathComponent("Two.txt"))
        try applyEvent(for: original, isDirectory: true, in: fixture)
        XCTAssertEqual(try fixture.store.fileCount(), 2)

        let renamed = fixture.root.appendingPathComponent("Renamed", isDirectory: true)
        try FileManager.default.moveItem(at: original, to: renamed)
        try applyEvents(
            [
                FileSystemEvent(
                    path: original.path,
                    isDirectory: true,
                    requiresFullRescan: false
                ),
                FileSystemEvent(
                    path: renamed.path,
                    isDirectory: true,
                    requiresFullRescan: false
                )
            ],
            in: fixture
        )

        let indexedPaths = try fixture.store.allFiles().map(\.path)
        XCTAssertEqual(indexedPaths.count, 2)
        XCTAssertTrue(indexedPaths.allSatisfy { $0.hasPrefix(renamed.path + "/") })
    }

    func testDroppedEventsTriggerAFullRootReconciliation() throws {
        let fixture = try makeIncrementalFixture()
        defer { fixture.cleanup() }

        let stale = fixture.root.appendingPathComponent("Stale.txt")
        try Data("old".utf8).write(to: stale)
        try fixture.store.replaceIndex(
            with: FilenameIndex.scan(locations: [fixture.root]),
            roots: [fixture.root]
        )

        try FileManager.default.removeItem(at: stale)
        let recovered = fixture.root.appendingPathComponent("Recovered.txt")
        try Data("new".utf8).write(to: recovered)
        try applyEvents(
            [
                FileSystemEvent(
                    path: fixture.root.path,
                    isDirectory: true,
                    requiresFullRescan: true
                )
            ],
            in: fixture
        )

        XCTAssertEqual(try fixture.store.allFiles().map(\.path), [recovered.path])
    }

    func testFolderWatcherDeliversARealCreatedFileEvent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let root = directory.resolvingSymlinksInPath()
        let created = root.appendingPathComponent("Watched File.txt")
        defer { try? FileManager.default.removeItem(at: root) }

        let watcher = FSEventsFolderWatcher()
        let receivedEvent = expectation(description: "FSEvents reports the created file")
        watcher.onEvents = { events in
            guard events.contains(where: {
                URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path
                    == created.path
            }) else { return }
            receivedEvent.fulfill()
        }
        watcher.start(watching: [root])
        defer { watcher.stop() }

        try Data("live".utf8).write(to: created)

        wait(for: [receivedEvent], timeout: 5)
    }

    func testMigratesLegacyApplicationSupportDirectory() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyDirectory = applicationSupport.appendingPathComponent(
            "Vez",
            isDirectory: true
        )
        let legacyDatabase = legacyDirectory.appendingPathComponent("index.sqlite")
        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        try Data("legacy-index".utf8).write(to: legacyDatabase)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }

        let migratedDirectory = try XCTUnwrap(
            FilenameIndex.prepareApplicationSupportDirectory(at: applicationSupport)
        )

        XCTAssertEqual(migratedDirectory.lastPathComponent, "SpotAlt")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: migratedDirectory.appendingPathComponent("index.sqlite").path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDirectory.path))
    }

    private func file(named name: String) -> IndexedFile {
        IndexedFile(
            name: name,
            path: "/Users/test/Documents/\(name)",
            modifiedAt: nil
        )
    }

    private func makeIncrementalFixture() throws -> (
        root: URL,
        store: SQLiteIndexStore,
        cleanup: () -> Void
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let requestedRoot = directory.appendingPathComponent("Enrolled", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("Database/index.sqlite")
        try FileManager.default.createDirectory(
            at: requestedRoot,
            withIntermediateDirectories: true
        )
        let root = requestedRoot.resolvingSymlinksInPath()
        let store = try SQLiteIndexStore(databaseURL: databaseURL)
        try store.synchronizeRoots([root])
        return (
            root,
            store,
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    private func applyEvent(
        for url: URL,
        isDirectory: Bool = false,
        in fixture: (root: URL, store: SQLiteIndexStore, cleanup: () -> Void)
    ) throws {
        try applyEvents(
            [
                FileSystemEvent(
                    path: url.path,
                    isDirectory: isDirectory,
                    requiresFullRescan: false
                )
            ],
            in: fixture
        )
    }

    private func applyEvents(
        _ events: [FileSystemEvent],
        in fixture: (root: URL, store: SQLiteIndexStore, cleanup: () -> Void)
    ) throws {
        _ = try FilenameIndex.applyFileSystemEvents(
            events,
            roots: [fixture.root],
            excludingPaths: [],
            to: fixture.store
        )
    }
}
