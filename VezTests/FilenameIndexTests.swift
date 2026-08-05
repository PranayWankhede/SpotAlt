import Foundation
import XCTest
@testable import Vez

final class FilenameIndexTests: XCTestCase {
    func testScanRecursivelyIndexesFilesAndSkipsCommonNoise() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("Projects/Vez", isDirectory: true)
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

    private func file(named name: String) -> IndexedFile {
        IndexedFile(
            name: name,
            path: "/Users/test/Documents/\(name)",
            modifiedAt: nil
        )
    }
}
