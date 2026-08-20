import AppKit
import Foundation
import PDFKit

struct FileContentUpdate {
    let file: IndexedFile
    let chunks: [String]
}

struct DocumentExtractionLimits {
    static let optimizedDefaults = DocumentExtractionLimits(
        maxPlainTextBytes: 5 * 1_024 * 1_024,
        maxDocumentBytes: 50 * 1_024 * 1_024,
        maxExtractedCharacters: 1_000_000,
        chunkCharacters: 2_000,
        chunkOverlapCharacters: 200,
        maxChunks: 512
    )

    let maxPlainTextBytes: Int64
    let maxDocumentBytes: Int64
    let maxExtractedCharacters: Int
    let chunkCharacters: Int
    let chunkOverlapCharacters: Int
    let maxChunks: Int
}

final class DocumentTextExtractor {
    static let extractionVersion = 1

    private static let plainTextExtensions: Set<String> = [
        "bash", "c", "cc", "cfg", "conf", "cpp", "css", "csv", "fish",
        "go", "h", "hpp", "htm", "html", "ini", "java", "js", "json",
        "jsonl", "jsx", "kt", "kts", "less", "log", "m", "markdown",
        "md", "mm", "php", "plist", "py", "rb", "rs", "scss", "sh",
        "sql", "swift", "toml", "ts", "tsx", "txt", "xml", "yaml", "yml",
        "zsh"
    ]

    private static let richTextTypes: [String: NSAttributedString.DocumentType] = [
        "doc": .docFormat,
        "docx": .officeOpenXML,
        "odt": .openDocument,
        "rtf": .rtf,
        "rtfd": .rtfd,
        "webarchive": .webArchive,
        "xmlword": .wordML
    ]

    private static let metadataImporterExtensions: Set<String> = [
        "key", "numbers", "pages", "ppt", "pptx", "xls", "xlsx"
    ]

    static let supportedPackageExtensions: Set<String> = [
        "key", "numbers", "pages", "rtfd"
    ]

    private let limits: DocumentExtractionLimits

    init(limits: DocumentExtractionLimits = .optimizedDefaults) {
        self.limits = limits
    }

    func extractContent(from file: IndexedFile) -> FileContentUpdate {
        let text = autoreleasepool {
            extractText(from: file)
        }
        return FileContentUpdate(
            file: file,
            chunks: text.map(makeChunks) ?? []
        )
    }

    static func canIndexPackage(at url: URL) -> Bool {
        supportedPackageExtensions.contains(url.pathExtension.lowercased())
    }

    private func extractText(from file: IndexedFile) -> String? {
        let fileExtension = file.url.pathExtension.lowercased()

        if Self.plainTextExtensions.contains(fileExtension) {
            guard isWithinLimit(file, limit: limits.maxPlainTextBytes) else {
                return nil
            }
            return readPlainText(from: file.url)
        }

        if fileExtension == "pdf" {
            guard isWithinLimit(file, limit: limits.maxDocumentBytes) else {
                return nil
            }
            return PDFDocument(url: file.url)?.string
        }

        if let documentType = Self.richTextTypes[fileExtension] {
            guard isWithinLimit(file, limit: limits.maxDocumentBytes) else {
                return nil
            }
            return try? NSAttributedString(
                url: file.url,
                options: [.documentType: documentType],
                documentAttributes: nil
            ).string
        }

        if Self.metadataImporterExtensions.contains(fileExtension) {
            guard isWithinLimit(file, limit: limits.maxDocumentBytes) else {
                return nil
            }
            return extractUsingMetadataImporter(from: file.url)
        }

        return nil
    }

    private func isWithinLimit(_ file: IndexedFile, limit: Int64) -> Bool {
        if let size = file.sizeBytes {
            return size >= 0 && size <= limit
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(
            atPath: file.path,
            isDirectory: &isDirectory
        ) else { return false }

        if !isDirectory.boolValue {
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            guard let size = attributes?[.size] as? NSNumber else { return false }
            return size.int64Value <= limit
        }

        guard Self.canIndexPackage(at: file.url),
              let enumerator = FileManager.default.enumerator(
                  at: file.url,
                  includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                  options: [.skipsHiddenFiles],
                  errorHandler: { _, _ in false }
              )
        else { return false }

        var totalSize: Int64 = 0
        for case let itemURL as URL in enumerator {
            guard let values = try? itemURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ), values.isRegularFile == true else { continue }
            totalSize += Int64(values.fileSize ?? 0)
            if totalSize > limit { return false }
        }
        return true
    }

    private func readPlainText(from url: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fileHandle.close() }

        guard let data = try? fileHandle.read(upToCount: Int(limits.maxPlainTextBytes) + 1),
              data.count <= limits.maxPlainTextBytes
        else { return nil }

        if data.prefix(4_096).contains(0) {
            return String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .utf16LittleEndian)
                ?? String(data: data, encoding: .utf16BigEndian)
        }

        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(data: data, encoding: .macOSRoman)
    }

    private func extractUsingMetadataImporter(from url: URL) -> String? {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "spotalt-metadata-\(UUID().uuidString).plist"
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdimport")
        process.arguments = ["-t", "-o", outputURL.path, url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        guard completed.wait(timeout: .now() + 15) == .success else {
            process.terminate()
            process.waitUntilExit()
            return nil
        }
        guard process.terminationStatus == 0,
              let data = try? Data(contentsOf: outputURL),
              let attributes = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any]
        else { return nil }

        return attributes["kMDItemTextContent"] as? String
    }

    private func makeChunks(from text: String) -> [String] {
        let cappedText = String(text.prefix(limits.maxExtractedCharacters))
        let normalizedText = Self.collapsingWhitespace(in: cappedText)
        guard normalizedText.count > 1 else { return [] }

        let source = normalizedText as NSString
        var chunks: [String] = []
        chunks.reserveCapacity(
            min(
                limits.maxChunks,
                max(1, source.length / limits.chunkCharacters + 1)
            )
        )
        var start = 0

        while start < source.length && chunks.count < limits.maxChunks {
            let proposedEnd = min(start + limits.chunkCharacters, source.length)
            var end = proposedEnd

            if proposedEnd < source.length {
                let minimumBreak = min(
                    proposedEnd,
                    start + (limits.chunkCharacters * 3 / 4)
                )
                let breakRange = source.rangeOfCharacter(
                    from: .whitespacesAndNewlines,
                    options: .backwards,
                    range: NSRange(
                        location: minimumBreak,
                        length: proposedEnd - minimumBreak
                    )
                )
                if breakRange.location != NSNotFound {
                    end = breakRange.location
                }
            }

            let safeRange = source.rangeOfComposedCharacterSequences(
                for: NSRange(location: start, length: max(1, end - start))
            )
            let chunk = source.substring(with: safeRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(chunk)
            }

            guard end < source.length else { break }
            start = max(start + 1, end - limits.chunkOverlapCharacters)
        }

        return chunks
    }

    private static func collapsingWhitespace(in text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        var needsSpace = false

        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                needsSpace = !result.isEmpty
                continue
            }
            if needsSpace {
                result.append(" ")
                needsSpace = false
            }
            result.unicodeScalars.append(scalar)
        }

        return result
    }
}
