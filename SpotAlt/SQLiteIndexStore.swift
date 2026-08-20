import Foundation
import SQLite3

enum SQLiteIndexStoreError: Error, LocalizedError {
    case openDatabase(String)
    case execute(String)
    case prepare(String)
    case bind(String)
    case corruptDatabase

    var errorDescription: String? {
        switch self {
        case .openDatabase(let message):
            "Could not open the SpotAlt index: \(message)"
        case .execute(let message):
            "Could not update the SpotAlt index: \(message)"
        case .prepare(let message):
            "Could not prepare a SpotAlt index query: \(message)"
        case .bind(let message):
            "Could not bind a SpotAlt index value: \(message)"
        case .corruptDatabase:
            "The SpotAlt index is corrupt."
        }
    }
}

struct ContentSearchHit {
    let file: IndexedFile
    let excerpt: String
    let rank: Double
}

final class SQLiteIndexStore {
    static let schemaVersion = 2

    private static let transientDestructor = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

    private let databaseURL: URL
    private let writeLock = NSLock()
    private let readLock = NSLock()
    private var database: OpaquePointer?
    private var readDatabase: OpaquePointer?

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            try openAndConfigure()
        } catch {
            closeDatabase()
            removeDatabaseFiles()
            try openAndConfigure()
        }
    }

    deinit {
        closeDatabase()
    }

    func synchronizeRoots(_ roots: [URL]) throws {
        try withWriteLock {
            try transaction {
                let activePaths = Set(roots.map { Self.canonicalPath($0) })
                let existingRoots = try rootRows()

                for root in existingRoots where !activePaths.contains(root.path) {
                    try execute("DELETE FROM search_roots WHERE id = \(root.id);")
                }

                let statement = try prepare(
                    "INSERT OR IGNORE INTO search_roots(path) VALUES (?);"
                )
                defer { sqlite3_finalize(statement) }

                for path in activePaths.sorted() {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    try bind(path, to: statement, at: 1)
                    try stepDone(statement)
                }
            }
        }
    }

    func replaceIndex(with files: [IndexedFile], roots: [URL]) throws {
        try withWriteLock {
            try transaction {
                let activePaths = Set(roots.map { Self.canonicalPath($0) })
                for root in try rootRows() where !activePaths.contains(root.path) {
                    try execute("DELETE FROM search_roots WHERE id = \(root.id);")
                }

                let insertRoot = try prepare(
                    """
                    INSERT INTO search_roots(path, last_indexed_at) VALUES (?, ?)
                    ON CONFLICT(path) DO UPDATE SET
                        last_indexed_at = excluded.last_indexed_at;
                    """
                )
                defer { sqlite3_finalize(insertRoot) }

                for path in activePaths.sorted() {
                    sqlite3_reset(insertRoot)
                    sqlite3_clear_bindings(insertRoot)
                    try bind(path, to: insertRoot, at: 1)
                    try bind(Date().timeIntervalSince1970, to: insertRoot, at: 2)
                    try stepDone(insertRoot)
                }

                let rootRows = try rootRows()
                let rootPaths = rootRows.sorted { $0.path.count > $1.path.count }
                try execute(
                    "CREATE TEMP TABLE IF NOT EXISTS current_scan_paths(path TEXT PRIMARY KEY) WITHOUT ROWID;"
                )
                try execute("DELETE FROM current_scan_paths;")

                let insertScannedPath = try prepare(
                    "INSERT OR IGNORE INTO current_scan_paths(path) VALUES (?);"
                )
                defer { sqlite3_finalize(insertScannedPath) }
                let insertFile = try prepare(
                    """
                    INSERT INTO files(
                        root_id,
                        filename,
                        normalized_filename,
                        full_path,
                        normalized_path,
                        modified_at,
                        size_bytes
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(full_path) DO UPDATE SET
                        root_id = excluded.root_id,
                        filename = excluded.filename,
                        normalized_filename = excluded.normalized_filename,
                        normalized_path = excluded.normalized_path,
                        modified_at = excluded.modified_at,
                        size_bytes = excluded.size_bytes;
                    """
                )
                defer { sqlite3_finalize(insertFile) }

                for file in files {
                    guard let root = rootPaths.first(where: {
                        Self.contains(filePath: file.path, rootPath: $0.path)
                    }) else {
                        continue
                    }

                    sqlite3_reset(insertScannedPath)
                    sqlite3_clear_bindings(insertScannedPath)
                    try bind(file.path, to: insertScannedPath, at: 1)
                    try stepDone(insertScannedPath)

                    sqlite3_reset(insertFile)
                    sqlite3_clear_bindings(insertFile)
                    try bind(root.id, to: insertFile, at: 1)
                    try bind(file.name, to: insertFile, at: 2)
                    try bind(SearchTextNormalizer.normalize(file.name), to: insertFile, at: 3)
                    try bind(file.path, to: insertFile, at: 4)
                    try bind(SearchTextNormalizer.normalize(file.parentPath), to: insertFile, at: 5)
                    if let modifiedAt = file.modifiedAt {
                        try bind(modifiedAt.timeIntervalSince1970, to: insertFile, at: 6)
                    } else {
                        sqlite3_bind_null(insertFile, 6)
                    }
                    if let sizeBytes = file.sizeBytes {
                        try bind(sizeBytes, to: insertFile, at: 7)
                    } else {
                        sqlite3_bind_null(insertFile, 7)
                    }
                    try stepDone(insertFile)
                }

                try execute(
                    "DELETE FROM files WHERE full_path NOT IN (SELECT path FROM current_scan_paths);"
                )
            }
        }
    }

    @discardableResult
    func applyChanges(
        upserting files: [IndexedFile],
        deletingPaths: Set<String>,
        deletingSubtrees: Set<String>
    ) throws -> Int {
        try withWriteLock {
            try transaction {
                let deletePath = try prepare(
                    "DELETE FROM files WHERE full_path = ?;"
                )
                defer { sqlite3_finalize(deletePath) }

                for path in deletingPaths.sorted() {
                    sqlite3_reset(deletePath)
                    sqlite3_clear_bindings(deletePath)
                    try bind(path, to: deletePath, at: 1)
                    try stepDone(deletePath)
                }

                let deleteSubtree = try prepare(
                    """
                    DELETE FROM files
                    WHERE full_path = ?
                       OR full_path LIKE ? ESCAPE '\\';
                    """
                )
                defer { sqlite3_finalize(deleteSubtree) }

                for path in deletingSubtrees.sorted() {
                    sqlite3_reset(deleteSubtree)
                    sqlite3_clear_bindings(deleteSubtree)
                    try bind(path, to: deleteSubtree, at: 1)
                    try bind(
                        "\(Self.escapeLike(path))/%",
                        to: deleteSubtree,
                        at: 2
                    )
                    try stepDone(deleteSubtree)
                }

                let roots = try rootRows()
                let rootPaths = roots.sorted { lhs, rhs in
                    lhs.path.count > rhs.path.count
                }
                let upsert = try prepare(
                    """
                    INSERT INTO files(
                        root_id,
                        filename,
                        normalized_filename,
                        full_path,
                        normalized_path,
                        modified_at,
                        size_bytes
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(full_path) DO UPDATE SET
                        root_id = excluded.root_id,
                        filename = excluded.filename,
                        normalized_filename = excluded.normalized_filename,
                        normalized_path = excluded.normalized_path,
                        modified_at = excluded.modified_at,
                        size_bytes = excluded.size_bytes;
                    """
                )
                defer { sqlite3_finalize(upsert) }

                for file in files {
                    guard let root = rootPaths.first(where: {
                        Self.contains(filePath: file.path, rootPath: $0.path)
                    }) else { continue }

                    sqlite3_reset(upsert)
                    sqlite3_clear_bindings(upsert)
                    try bind(root.id, to: upsert, at: 1)
                    try bind(file.name, to: upsert, at: 2)
                    try bind(
                        SearchTextNormalizer.normalize(file.name),
                        to: upsert,
                        at: 3
                    )
                    try bind(file.path, to: upsert, at: 4)
                    try bind(
                        SearchTextNormalizer.normalize(file.parentPath),
                        to: upsert,
                        at: 5
                    )
                    if let modifiedAt = file.modifiedAt {
                        try bind(modifiedAt.timeIntervalSince1970, to: upsert, at: 6)
                    } else {
                        sqlite3_bind_null(upsert, 6)
                    }
                    if let sizeBytes = file.sizeBytes {
                        try bind(sizeBytes, to: upsert, at: 7)
                    } else {
                        sqlite3_bind_null(upsert, 7)
                    }
                    try stepDone(upsert)
                }
            }

            return try fileCountWithoutLock()
        }
    }

    func searchCandidates(for query: String, limit: Int = 1_000) throws -> [IndexedFile] {
        let normalizedQuery = SearchTextNormalizer.normalize(query)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        return try withReadLock {
            let terms = normalizedQuery
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
            let termClauses = terms.map { _ in
                "(normalized_filename LIKE ? ESCAPE '\\' OR normalized_path LIKE ? ESCAPE '\\')"
            }
            let filter = termClauses.joined(separator: " AND ")
            let sql = """
                SELECT filename, full_path, modified_at, size_bytes
                FROM files
                WHERE \(filter)
                   OR normalized_filename GLOB ?
                ORDER BY
                    CASE
                        WHEN normalized_filename = ? THEN 0
                        WHEN normalized_filename LIKE ? ESCAPE '\\' THEN 1
                        WHEN normalized_filename LIKE ? ESCAPE '\\' THEN 2
                        ELSE 3
                    END,
                    modified_at DESC,
                    filename COLLATE NOCASE ASC
                LIMIT ?;
                """
            let statement = try prepareRead(sql)
            defer { sqlite3_finalize(statement) }

            var parameter: Int32 = 1
            for term in terms {
                let pattern = "%\(Self.escapeLike(term))%"
                try bind(pattern, to: statement, at: parameter)
                parameter += 1
                try bind(pattern, to: statement, at: parameter)
                parameter += 1
            }

            try bind(Self.subsequenceGlob(normalizedQuery), to: statement, at: parameter)
            parameter += 1
            try bind(normalizedQuery, to: statement, at: parameter)
            parameter += 1
            try bind("\(Self.escapeLike(normalizedQuery))%", to: statement, at: parameter)
            parameter += 1
            try bind("%\(Self.escapeLike(normalizedQuery))%", to: statement, at: parameter)
            parameter += 1
            try bind(Int64(limit), to: statement, at: parameter)

            return try readFiles(from: statement, database: readDatabase)
        }
    }

    func allFiles() throws -> [IndexedFile] {
        try withWriteLock {
            let statement = try prepare(
                "SELECT filename, full_path, modified_at, size_bytes FROM files ORDER BY full_path;"
            )
            defer { sqlite3_finalize(statement) }
            return try readFiles(from: statement)
        }
    }

    func fileCount() throws -> Int {
        try withWriteLock {
            try fileCountWithoutLock()
        }
    }

    func pendingContentFiles(
        extractionVersion: Int,
        limit: Int = 24
    ) throws -> [IndexedFile] {
        try withWriteLock {
            let statement = try prepare(
                """
                SELECT filename, full_path, modified_at, size_bytes
                FROM files
                WHERE content_index_version <> ?
                ORDER BY
                    CASE WHEN size_bytes IS NULL THEN 1 ELSE 0 END,
                    size_bytes ASC,
                    full_path ASC
                LIMIT ?;
                """
            )
            defer { sqlite3_finalize(statement) }
            try bind(Int64(extractionVersion), to: statement, at: 1)
            try bind(Int64(limit), to: statement, at: 2)
            return try readFiles(from: statement)
        }
    }

    func applyContentUpdates(
        _ updates: [FileContentUpdate],
        extractionVersion: Int
    ) throws {
        guard !updates.isEmpty else { return }

        try withWriteLock {
            try transaction {
                let findFile = try prepare(
                    """
                    SELECT id FROM files
                    WHERE full_path = ?
                      AND modified_at IS ?
                      AND size_bytes IS ?;
                    """
                )
                defer { sqlite3_finalize(findFile) }

                let deleteChunks = try prepare(
                    "DELETE FROM content_fts WHERE file_id = ?;"
                )
                defer { sqlite3_finalize(deleteChunks) }

                let insertChunk = try prepare(
                    "INSERT INTO content_fts(file_id, chunk_index, content) VALUES (?, ?, ?);"
                )
                defer { sqlite3_finalize(insertChunk) }

                let markIndexed = try prepare(
                    "UPDATE files SET content_index_version = ? WHERE id = ?;"
                )
                defer { sqlite3_finalize(markIndexed) }

                for update in updates {
                    sqlite3_reset(findFile)
                    sqlite3_clear_bindings(findFile)
                    try bind(update.file.path, to: findFile, at: 1)
                    try bind(update.file.modifiedAt?.timeIntervalSince1970, to: findFile, at: 2)
                    try bind(update.file.sizeBytes, to: findFile, at: 3)

                    guard sqlite3_step(findFile) == SQLITE_ROW else { continue }
                    let fileID = sqlite3_column_int64(findFile, 0)

                    sqlite3_reset(deleteChunks)
                    sqlite3_clear_bindings(deleteChunks)
                    try bind(fileID, to: deleteChunks, at: 1)
                    try stepDone(deleteChunks)

                    for (chunkIndex, chunk) in update.chunks.enumerated() {
                        sqlite3_reset(insertChunk)
                        sqlite3_clear_bindings(insertChunk)
                        try bind(fileID, to: insertChunk, at: 1)
                        try bind(Int64(chunkIndex), to: insertChunk, at: 2)
                        try bind(chunk, to: insertChunk, at: 3)
                        try stepDone(insertChunk)
                    }

                    sqlite3_reset(markIndexed)
                    sqlite3_clear_bindings(markIndexed)
                    try bind(Int64(extractionVersion), to: markIndexed, at: 1)
                    try bind(fileID, to: markIndexed, at: 2)
                    try stepDone(markIndexed)
                }
            }
        }
    }

    func searchContent(for query: String, limit: Int = 100) throws -> [ContentSearchHit] {
        guard let matchQuery = Self.ftsMatchQuery(query) else { return [] }

        return try withReadLock {
            let statement = try prepareRead(
                """
                SELECT
                    files.filename,
                    files.full_path,
                    files.modified_at,
                    files.size_bytes,
                    snippet(content_fts, 2, '‹', '›', ' … ', 20),
                    bm25(content_fts, 0.0, 0.0, 1.0)
                FROM content_fts
                JOIN files ON files.id = content_fts.file_id
                WHERE content_fts MATCH ?
                ORDER BY bm25(content_fts, 0.0, 0.0, 1.0) ASC
                LIMIT ?;
                """
            )
            defer { sqlite3_finalize(statement) }
            try bind(matchQuery, to: statement, at: 1)
            try bind(Int64(max(limit * 4, limit)), to: statement, at: 2)

            var hits: [ContentSearchHit] = []
            var seenPaths: Set<String> = []
            while hits.count < limit {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else {
                    throw SQLiteIndexStoreError.execute(
                        Self.errorMessage(for: readDatabase)
                    )
                }
                guard let name = sqlite3_column_text(statement, 0),
                      let path = sqlite3_column_text(statement, 1),
                      let excerpt = sqlite3_column_text(statement, 4)
                else { continue }

                let pathValue = String(cString: path)
                guard seenPaths.insert(pathValue).inserted else { continue }

                let modifiedAt: Date?
                if sqlite3_column_type(statement, 2) == SQLITE_NULL {
                    modifiedAt = nil
                } else {
                    modifiedAt = Date(
                        timeIntervalSince1970: sqlite3_column_double(statement, 2)
                    )
                }
                let sizeBytes: Int64? = sqlite3_column_type(statement, 3) == SQLITE_NULL
                    ? nil
                    : sqlite3_column_int64(statement, 3)
                hits.append(
                    ContentSearchHit(
                        file: IndexedFile(
                            name: String(cString: name),
                            path: pathValue,
                            modifiedAt: modifiedAt,
                            sizeBytes: sizeBytes
                        ),
                        excerpt: String(cString: excerpt),
                        rank: sqlite3_column_double(statement, 5)
                    )
                )
            }
            return hits
        }
    }

    private func openAndConfigure() throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK else {
            let message = lastErrorMessage
            closeDatabase()
            throw SQLiteIndexStoreError.openDatabase(message)
        }

        sqlite3_busy_timeout(database, 5_000)
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
        try verifyIntegrity()
        try migrateSchema()

        let readFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(
            databaseURL.path,
            &readDatabase,
            readFlags,
            nil
        ) == SQLITE_OK else {
            throw SQLiteIndexStoreError.openDatabase(
                Self.errorMessage(for: readDatabase)
            )
        }
        sqlite3_busy_timeout(readDatabase, 5_000)
    }

    private func verifyIntegrity() throws {
        let statement = try prepare("PRAGMA quick_check;")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let result = sqlite3_column_text(statement, 0),
              String(cString: result) == "ok" else {
            throw SQLiteIndexStoreError.corruptDatabase
        }
    }

    private func migrateSchema() throws {
        let version = try schemaVersion()
        guard version <= Self.schemaVersion else {
            throw SQLiteIndexStoreError.corruptDatabase
        }

        if version < 1 {
            try transaction {
                try execute(
                    """
                    CREATE TABLE IF NOT EXISTS search_roots(
                        id INTEGER PRIMARY KEY,
                        path TEXT NOT NULL UNIQUE,
                        last_indexed_at REAL
                    );
                    """
                )
                try execute(
                    """
                    CREATE TABLE IF NOT EXISTS files(
                        id INTEGER PRIMARY KEY,
                        root_id INTEGER NOT NULL REFERENCES search_roots(id) ON DELETE CASCADE,
                        filename TEXT NOT NULL,
                        normalized_filename TEXT NOT NULL,
                        full_path TEXT NOT NULL UNIQUE,
                        normalized_path TEXT NOT NULL,
                        modified_at REAL
                    );
                    """
                )
                try execute(
                    "CREATE INDEX IF NOT EXISTS files_normalized_filename ON files(normalized_filename);"
                )
                try execute(
                    "CREATE INDEX IF NOT EXISTS files_normalized_path ON files(normalized_path);"
                )
                try execute(
                    "CREATE INDEX IF NOT EXISTS files_root_id ON files(root_id);"
                )
                try execute("PRAGMA user_version = 1;")
            }
        }

        if version < 2 {
            try transaction {
                try execute("ALTER TABLE files ADD COLUMN size_bytes INTEGER;")
                try execute(
                    "ALTER TABLE files ADD COLUMN content_index_version INTEGER NOT NULL DEFAULT 0;"
                )
                try execute(
                    """
                    CREATE VIRTUAL TABLE content_fts USING fts5(
                        file_id UNINDEXED,
                        chunk_index UNINDEXED,
                        content,
                        tokenize = 'unicode61 remove_diacritics 2'
                    );
                    """
                )
                try execute(
                    """
                    CREATE TRIGGER files_delete_content
                    BEFORE DELETE ON files
                    BEGIN
                        DELETE FROM content_fts WHERE file_id = OLD.id;
                    END;
                    """
                )
                try execute(
                    """
                    CREATE TRIGGER files_invalidate_content
                    AFTER UPDATE OF modified_at, size_bytes ON files
                    WHEN OLD.modified_at IS NOT NEW.modified_at
                      OR OLD.size_bytes IS NOT NEW.size_bytes
                    BEGIN
                        DELETE FROM content_fts WHERE file_id = NEW.id;
                        UPDATE files
                        SET content_index_version = 0
                        WHERE id = NEW.id;
                    END;
                    """
                )
                try execute("PRAGMA user_version = 2;")
            }
        }
    }

    private func schemaVersion() throws -> Int {
        let statement = try prepare("PRAGMA user_version;")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteIndexStoreError.execute(lastErrorMessage)
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func rootRows() throws -> [(id: Int64, path: String)] {
        let statement = try prepare("SELECT id, path FROM search_roots;")
        defer { sqlite3_finalize(statement) }
        var rows: [(Int64, String)] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let path = sqlite3_column_text(statement, 1) else { continue }
            rows.append((sqlite3_column_int64(statement, 0), String(cString: path)))
        }
        return rows
    }

    private func fileCountWithoutLock() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM files;")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteIndexStoreError.execute(lastErrorMessage)
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func readFiles(
        from statement: OpaquePointer?,
        database: OpaquePointer? = nil
    ) throws -> [IndexedFile] {
        var files: [IndexedFile] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return files
            }
            guard result == SQLITE_ROW else {
                throw SQLiteIndexStoreError.execute(
                    Self.errorMessage(for: database ?? self.database)
                )
            }
            guard let name = sqlite3_column_text(statement, 0),
                  let path = sqlite3_column_text(statement, 1) else {
                continue
            }

            let modifiedAt: Date?
            if sqlite3_column_type(statement, 2) == SQLITE_NULL {
                modifiedAt = nil
            } else {
                modifiedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            }
            let sizeBytes: Int64? = sqlite3_column_type(statement, 3) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(statement, 3)
            files.append(
                IndexedFile(
                    name: String(cString: name),
                    path: String(cString: path),
                    modifiedAt: modifiedAt,
                    sizeBytes: sizeBytes
                )
            )
        }
    }

    private func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try work()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        try prepare(sql, database: database)
    }

    private func prepareRead(_ sql: String) throws -> OpaquePointer? {
        try prepare(sql, database: readDatabase)
    }

    private func prepare(
        _ sql: String,
        database: OpaquePointer?
    ) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteIndexStoreError.prepare(Self.errorMessage(for: database))
        }
        return statement
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorMessage)
            throw SQLiteIndexStoreError.execute(message)
        }
    }

    private func bind(_ value: String, to statement: OpaquePointer?, at index: Int32) throws {
        let result = sqlite3_bind_text(
            statement,
            index,
            value,
            -1,
            Self.transientDestructor
        )
        guard result == SQLITE_OK else {
            throw SQLiteIndexStoreError.bind(String(cString: sqlite3_errstr(result)))
        }
    }

    private func bind(_ value: Int64, to statement: OpaquePointer?, at index: Int32) throws {
        let result = sqlite3_bind_int64(statement, index, value)
        guard result == SQLITE_OK else {
            throw SQLiteIndexStoreError.bind(String(cString: sqlite3_errstr(result)))
        }
    }

    private func bind(_ value: Double, to statement: OpaquePointer?, at index: Int32) throws {
        let result = sqlite3_bind_double(statement, index, value)
        guard result == SQLITE_OK else {
            throw SQLiteIndexStoreError.bind(String(cString: sqlite3_errstr(result)))
        }
    }

    private func bind(_ value: Double?, to statement: OpaquePointer?, at index: Int32) throws {
        if let value {
            try bind(value, to: statement, at: index)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(_ value: Int64?, to statement: OpaquePointer?, at index: Int32) throws {
        if let value {
            try bind(value, to: statement, at: index)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteIndexStoreError.execute(lastErrorMessage)
        }
    }

    private var lastErrorMessage: String {
        guard let database, let message = sqlite3_errmsg(database) else {
            return "Unknown SQLite error"
        }
        return String(cString: message)
    }

    private func withWriteLock<T>(_ work: () throws -> T) rethrows -> T {
        writeLock.lock()
        defer { writeLock.unlock() }
        return try work()
    }

    private func withReadLock<T>(_ work: () throws -> T) rethrows -> T {
        readLock.lock()
        defer { readLock.unlock() }
        return try work()
    }

    private func closeDatabase() {
        if let readDatabase {
            sqlite3_close_v2(readDatabase)
            self.readDatabase = nil
        }
        if let database {
            sqlite3_close_v2(database)
            self.database = nil
        }
    }

    private func removeDatabaseFiles() {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: databaseURL)
        try? fileManager.removeItem(atPath: databaseURL.path + "-wal")
        try? fileManager.removeItem(atPath: databaseURL.path + "-shm")
    }

    private static func contains(filePath: String, rootPath: String) -> Bool {
        filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static func subsequenceGlob(_ query: String) -> String {
        let escapedCharacters = query.map { character -> String in
            switch character {
            case "*": "[*]"
            case "?": "[?]"
            case "[": "[[]"
            case "]": "[]]"
            default: String(character)
            }
        }
        return "*" + escapedCharacters.joined(separator: "*") + "*"
    }

    private static func ftsMatchQuery(_ query: String) -> String? {
        let terms = SearchTextNormalizer.normalize(query)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
            .prefix(12)
        guard !terms.isEmpty else { return nil }

        return terms.map { term in
            let escaped = term.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\"*"
        }
        .joined(separator: " AND ")
    }

    private static func errorMessage(for database: OpaquePointer?) -> String {
        guard let database, let message = sqlite3_errmsg(database) else {
            return "Unknown SQLite error"
        }
        return String(cString: message)
    }
}

enum SearchTextNormalizer {
    static func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }
}
