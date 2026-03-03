import Foundation
#if canImport(Darwin)
import SQLite3
#else
import CSQLite3
#endif
import Ingest

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteStoreError: Error {
    case sqlite(String)
    case databaseClosed
    case missingRow(String)
    case embeddingDimensionMismatch(expected: Int, actual: Int)
}

public final class SQLiteStore: StorageWriting {
    private var db: OpaquePointer?
    private let expectedEmbeddingDimension: Int

    public init(databaseURL: URL, expectedEmbeddingDimension: Int) throws {
        self.expectedEmbeddingDimension = expectedEmbeddingDimension

        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var handle: OpaquePointer?
        if sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "failed to open sqlite database"
            sqlite3_close(handle)
            throw SQLiteStoreError.sqlite(message)
        }

        db = handle

        do {
            try execute("PRAGMA foreign_keys = ON;")
            try ensureSchema()
        } catch {
            sqlite3_close(handle)
            db = nil
            throw error
        }
    }

    deinit {
        sqlite3_close(db)
    }

    @discardableResult
    public func writeProcessedPage(_ request: ProcessedPageWriteRequest) throws -> WriteResult {
        guard request.embedding.dimension == expectedEmbeddingDimension else {
            throw SQLiteStoreError.embeddingDimensionMismatch(
                expected: expectedEmbeddingDimension,
                actual: request.embedding.dimension
            )
        }

        try execute("BEGIN IMMEDIATE;")
        do {
            let documentID = try upsertDocumentInTransaction(request.document)
            let pageID = try upsertPageInTransaction(documentID: documentID, page: request.page)
            try upsertEmbeddingInTransaction(pageID: pageID, embedding: request.embedding)
            try execute("COMMIT;")
            return WriteResult(documentID: documentID, pageID: pageID)
        } catch {
            _ = try? execute("ROLLBACK;")
            throw error
        }
    }

    public func upsertDocument(_ input: DocumentUpsertInput) throws -> Int64 {
        try execute("BEGIN IMMEDIATE;")
        do {
            let id = try upsertDocumentInTransaction(input)
            try execute("COMMIT;")
            return id
        } catch {
            _ = try? execute("ROLLBACK;")
            throw error
        }
    }

    public func upsertPage(documentID: Int64, page: PageUpsertInput) throws -> Int64 {
        try execute("BEGIN IMMEDIATE;")
        do {
            let id = try upsertPageInTransaction(documentID: documentID, page: page)
            try execute("COMMIT;")
            return id
        } catch {
            _ = try? execute("ROLLBACK;")
            throw error
        }
    }

    public func upsertPageEmbedding(pageID: Int64, embedding: EmbeddingResult) throws {
        guard embedding.dimension == expectedEmbeddingDimension else {
            throw SQLiteStoreError.embeddingDimensionMismatch(
                expected: expectedEmbeddingDimension,
                actual: embedding.dimension
            )
        }

        try execute("BEGIN IMMEDIATE;")
        do {
            try upsertEmbeddingInTransaction(pageID: pageID, embedding: embedding)
            try execute("COMMIT;")
        } catch {
            _ = try? execute("ROLLBACK;")
            throw error
        }
    }

    private func upsertDocumentInTransaction(_ input: DocumentUpsertInput) throws -> Int64 {
        try execute(
            """
            INSERT INTO documents (source_url, source_sha256, source_filename, source_label, document_title, source_unit, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            ON CONFLICT(source_sha256) DO UPDATE SET
              source_url = excluded.source_url,
              source_filename = excluded.source_filename,
              source_label = excluded.source_label,
              document_title = excluded.document_title,
              source_unit = excluded.source_unit,
              updated_at = CURRENT_TIMESTAMP;
            """,
            binds: [
                .text(input.sourceURL),
                .text(input.sourceSHA256),
                .text(input.sourceFilename),
                .text(input.sourceLabel),
                .text(input.documentTitle),
                .text(input.sourceUnit)
            ]
        )

        guard let id = try queryInt64(
            "SELECT id FROM documents WHERE source_sha256 = ? LIMIT 1;",
            binds: [.text(input.sourceSHA256)]
        ) else {
            throw SQLiteStoreError.missingRow("document upsert did not return id")
        }

        return id
    }

    private func upsertPageInTransaction(documentID: Int64, page: PageUpsertInput) throws -> Int64 {
        try execute(
            """
            INSERT INTO pages (
              document_id, page_number, ocr_version, extraction_method,
              orientation_degrees, dpi, quality_score, confidence,
              text_content, normalized_text_content, numeric_sanity_status,
              created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            ON CONFLICT(document_id, page_number, ocr_version) DO UPDATE SET
              extraction_method = excluded.extraction_method,
              orientation_degrees = excluded.orientation_degrees,
              dpi = excluded.dpi,
              quality_score = excluded.quality_score,
              confidence = excluded.confidence,
              text_content = excluded.text_content,
              normalized_text_content = excluded.normalized_text_content,
              numeric_sanity_status = excluded.numeric_sanity_status,
              updated_at = CURRENT_TIMESTAMP;
            """,
            binds: [
                .int(documentID),
                .int(Int64(page.pageNumber)),
                .text(page.ocrVersion),
                .text(page.extractionMethod),
                .int(Int64(page.orientationDegrees)),
                .int(Int64(page.dpi)),
                .double(page.qualityScore),
                .double(page.confidence),
                .text(page.textContent),
                .text(page.normalizedTextContent),
                .text(page.numericSanityStatus ?? "clean")
            ]
        )

        guard let pageID = try queryInt64(
            """
            SELECT id FROM pages
            WHERE document_id = ? AND page_number = ? AND ocr_version = ?
            LIMIT 1;
            """,
            binds: [
                .int(documentID),
                .int(Int64(page.pageNumber)),
                .text(page.ocrVersion)
            ]
        ) else {
            throw SQLiteStoreError.missingRow("page upsert did not return id")
        }

        return pageID
    }

    private func upsertEmbeddingInTransaction(pageID: Int64, embedding: EmbeddingResult) throws {
        let blob = serialize(vector: embedding.vector)

        try execute(
            """
            INSERT INTO page_embeddings (page_id, embedding_model_version, embedding_vector, vector_dim, created_at)
            VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(page_id, embedding_model_version) DO UPDATE SET
              embedding_vector = excluded.embedding_vector,
              vector_dim = excluded.vector_dim,
              created_at = CURRENT_TIMESTAMP;
            """,
            binds: [
                .int(pageID),
                .text(embedding.modelVersion),
                .blob(blob),
                .int(Int64(embedding.dimension))
            ]
        )
    }

    private func ensureSchema() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS documents (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              source_url TEXT,
              source_sha256 TEXT NOT NULL UNIQUE,
              source_filename TEXT,
              source_label TEXT,
              document_title TEXT,
              source_unit TEXT,
              created_at TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP),
              updated_at TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP)
            );
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS pages (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              document_id INTEGER NOT NULL,
              page_number INTEGER NOT NULL,
              ocr_version TEXT NOT NULL,
              extraction_method TEXT NOT NULL DEFAULT 'text_layer' CHECK (extraction_method IN ('text_layer', 'vision_ocr')),
              orientation_degrees INTEGER NOT NULL,
              dpi INTEGER NOT NULL,
              quality_score REAL NOT NULL,
              confidence REAL,
              text_content TEXT NOT NULL,
              normalized_text_content TEXT,
              numeric_sanity_status TEXT,
              created_at TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP),
              updated_at TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP),
              FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE,
              UNIQUE(document_id, page_number, ocr_version)
            );
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS page_embeddings (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              page_id INTEGER NOT NULL,
              embedding_model_version TEXT NOT NULL,
              embedding_vector BLOB NOT NULL,
              vector_dim INTEGER NOT NULL,
              created_at TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP),
              FOREIGN KEY(page_id) REFERENCES pages(id) ON DELETE CASCADE,
              UNIQUE(page_id, embedding_model_version)
            );
            """
        )
    }

    @discardableResult
    private func execute(_ sql: String, binds: [BindValue] = []) throws -> Int32 {
        guard let db else { throw SQLiteStoreError.databaseClosed }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.sqlite(lastSQLiteMessage())
        }
        defer { sqlite3_finalize(statement) }

        try bind(values: binds, to: statement)

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE || stepResult == SQLITE_ROW else {
            throw SQLiteStoreError.sqlite(lastSQLiteMessage())
        }

        return sqlite3_changes(db)
    }

    private func queryInt64(_ sql: String, binds: [BindValue]) throws -> Int64? {
        guard let db else { throw SQLiteStoreError.databaseClosed }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.sqlite(lastSQLiteMessage())
        }
        defer { sqlite3_finalize(statement) }

        try bind(values: binds, to: statement)

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_ROW || stepResult == SQLITE_DONE else {
            throw SQLiteStoreError.sqlite(lastSQLiteMessage())
        }

        guard stepResult == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(statement, 0)
    }

    private func bind(values: [BindValue], to statement: OpaquePointer?) throws {
        for (index, value) in values.enumerated() {
            let sqliteIndex = Int32(index + 1)
            let result: Int32
            switch value {
            case .int(let intValue):
                result = sqlite3_bind_int64(statement, sqliteIndex, intValue)
            case .double(let doubleValue):
                if let doubleValue {
                    result = sqlite3_bind_double(statement, sqliteIndex, doubleValue)
                } else {
                    result = sqlite3_bind_null(statement, sqliteIndex)
                }
            case .text(let textValue):
                if let textValue {
                    result = sqlite3_bind_text(statement, sqliteIndex, textValue, -1, SQLITE_TRANSIENT)
                } else {
                    result = sqlite3_bind_null(statement, sqliteIndex)
                }
            case .blob(let data):
                result = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, sqliteIndex, bytes.baseAddress, Int32(bytes.count), SQLITE_TRANSIENT)
                }
            }

            guard result == SQLITE_OK else {
                throw SQLiteStoreError.sqlite(lastSQLiteMessage())
            }
        }
    }

    private func serialize(vector: [Float]) -> Data {
        let immutable = vector
        return immutable.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func lastSQLiteMessage() -> String {
        guard let db else { return "database closed" }
        return String(cString: sqlite3_errmsg(db))
    }
}

private enum BindValue {
    case int(Int64)
    case double(Double?)
    case text(String?)
    case blob(Data)
}
