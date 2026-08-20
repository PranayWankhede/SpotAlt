import Foundation
import XCTest
@testable import SpotAlt

final class SQLiteIndexStoreTests: XCTestCase {
    func testStoresAndSearchesFilenameCandidates() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let root = URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)
        let invoice = file(
            named: "Café Invoice.pdf",
            in: root,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let roadmap = file(named: "Roadmap.md", in: root)

        try fixture.store.replaceIndex(with: [invoice, roadmap], roots: [root])

        XCTAssertEqual(try fixture.store.fileCount(), 2)
        XCTAssertEqual(
            try fixture.store.searchCandidates(for: "cafe invoice").map(\.path),
            [invoice.path]
        )
        XCTAssertEqual(
            try fixture.store.searchCandidates(for: "cfinv").map(\.path),
            [invoice.path]
        )
    }

    func testReplacingIndexRemovesStaleRecords() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let root = URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)
        let oldFile = file(named: "Old Notes.txt", in: root)
        let newFile = file(named: "New Notes.txt", in: root)

        try fixture.store.replaceIndex(with: [oldFile], roots: [root])
        try fixture.store.replaceIndex(with: [newFile], roots: [root])

        XCTAssertEqual(try fixture.store.allFiles().map(\.path), [newFile.path])
        XCTAssertTrue(try fixture.store.searchCandidates(for: "old").isEmpty)
    }

    func testIndexPersistsAcrossStoreInstances() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directory.appendingPathComponent("index.sqlite")
        let root = URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)
        let savedFile = file(named: "Saved Invoice.pdf", in: root)
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            let store = try SQLiteIndexStore(databaseURL: databaseURL)
            try store.replaceIndex(with: [savedFile], roots: [root])
        }

        let reopenedStore = try SQLiteIndexStore(databaseURL: databaseURL)

        XCTAssertEqual(try reopenedStore.fileCount(), 1)
        XCTAssertEqual(
            try reopenedStore.searchCandidates(for: "invoice").map(\.path),
            [savedFile.path]
        )
    }

    func testRemovingRootCascadesToItsFiles() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let documents = URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)
        let downloads = URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true)
        try fixture.store.replaceIndex(
            with: [
                file(named: "Document.txt", in: documents),
                file(named: "Download.txt", in: downloads)
            ],
            roots: [documents, downloads]
        )

        try fixture.store.synchronizeRoots([documents])

        XCTAssertEqual(try fixture.store.allFiles().map(\.name), ["Document.txt"])
    }

    func testCorruptDatabaseIsRebuiltSafely() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appendingPathComponent("index.sqlite")
        try Data("not a sqlite database".utf8).write(to: databaseURL)

        let store = try SQLiteIndexStore(databaseURL: databaseURL)

        XCTAssertEqual(try store.fileCount(), 0)
    }

    private func makeFixture() throws -> (
        store: SQLiteIndexStore,
        cleanup: () -> Void
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directory.appendingPathComponent("index.sqlite")
        let store = try SQLiteIndexStore(databaseURL: databaseURL)
        return (
            store,
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    private func file(
        named name: String,
        in root: URL,
        modifiedAt: Date? = nil
    ) -> IndexedFile {
        IndexedFile(
            name: name,
            path: root.appendingPathComponent(name).path,
            modifiedAt: modifiedAt
        )
    }
}
