import AppKit
import Foundation
import XCTest
@testable import SpotAlt

final class DocumentTextExtractorTests: XCTestCase {
    func testExtractsAndChunksPlainTextWithOverlapAndLimit() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("notes.md")
        let text = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda"
        try Data(text.utf8).write(to: fileURL)
        let extractor = DocumentTextExtractor(
            limits: DocumentExtractionLimits(
                maxPlainTextBytes: 1_024,
                maxDocumentBytes: 1_024,
                maxExtractedCharacters: 1_024,
                chunkCharacters: 24,
                chunkOverlapCharacters: 6,
                maxChunks: 2
            )
        )

        let update = extractor.extractContent(from: indexedFile(at: fileURL))

        XCTAssertEqual(update.chunks.count, 2)
        XCTAssertTrue(update.chunks[0].contains("alpha beta"))
        XCTAssertTrue(update.chunks[1].contains("gamma") || update.chunks[1].contains("delta"))
    }

    func testSkipsPlainTextOverConfiguredSizeLimit() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("large.txt")
        try Data("larger than four bytes".utf8).write(to: fileURL)
        let extractor = DocumentTextExtractor(
            limits: DocumentExtractionLimits(
                maxPlainTextBytes: 4,
                maxDocumentBytes: 4,
                maxExtractedCharacters: 100,
                chunkCharacters: 20,
                chunkOverlapCharacters: 2,
                maxChunks: 10
            )
        )

        XCTAssertTrue(
            extractor.extractContent(from: indexedFile(at: fileURL)).chunks.isEmpty
        )
    }

    func testExtractsRichTextDocument() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("proposal.rtf")
        let phrase = "Project Halcyon requires searchable document extraction."
        let attributedText = NSAttributedString(string: phrase)
        let data = try attributedText.data(
            from: NSRange(location: 0, length: attributedText.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        try data.write(to: fileURL)

        let chunks = DocumentTextExtractor()
            .extractContent(from: indexedFile(at: fileURL))
            .chunks

        XCTAssertTrue(chunks.joined(separator: " ").contains("Project Halcyon"))
    }

    func testExtractsWordDocument() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("proposal.docx")
        let packageURL = directory.appendingPathComponent("proposal-package.docx")
        let phrase = "Project Nebula appears inside a Word document."
        let attributedText = NSAttributedString(string: phrase)
        let wrapper = try attributedText.fileWrapper(
            from: NSRange(location: 0, length: attributedText.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.officeOpenXML
            ]
        )
        try wrapper.write(
            to: packageURL,
            options: .atomic,
            originalContentsURL: nil
        )
        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zipProcess.arguments = ["-c", "-k", "--norsrc", packageURL.path, fileURL.path]
        try zipProcess.run()
        zipProcess.waitUntilExit()
        XCTAssertEqual(zipProcess.terminationStatus, 0)

        let chunks = DocumentTextExtractor()
            .extractContent(from: indexedFile(at: fileURL))
            .chunks

        XCTAssertTrue(chunks.joined(separator: " ").contains("Project Nebula"))
    }

    func testExtractsSearchablePDF() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("brief.pdf")
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(
            CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        )
        context.beginPDFPage(nil)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        ("Project Aurora is searchable inside this PDF." as NSString).draw(
            at: NSPoint(x: 72, y: 700),
            withAttributes: [.font: NSFont.systemFont(ofSize: 16)]
        )
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        try data.write(to: fileURL)

        let chunks = DocumentTextExtractor()
            .extractContent(from: indexedFile(at: fileURL))
            .chunks

        XCTAssertTrue(chunks.joined(separator: " ").contains("Project Aurora"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func indexedFile(at url: URL) -> IndexedFile {
        let values = try? url.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        return IndexedFile(
            name: url.lastPathComponent,
            path: url.path,
            modifiedAt: values?.contentModificationDate,
            sizeBytes: values?.fileSize.map(Int64.init)
        )
    }
}
