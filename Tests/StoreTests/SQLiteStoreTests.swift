import Foundation
import SQLite3
import Testing
@testable import Store
@testable import Ingest

@Suite("SQLiteStore")
struct SQLiteStoreTests {
    @Test("writes document/page/embedding transactionally")
    func writesDocumentPageAndEmbeddingTransactionally() throws {
        let dbURL = temporaryDBURL()
        let writer = try SQLiteStore(databaseURL: dbURL, expectedEmbeddingDimension: 4)

        let request = ProcessedPageWriteRequest(
            document: DocumentUpsertInput(
                sourceSHA256: "sha-1",
                sourceURL: "https://example.com/report.pdf",
                sourceFilename: "report.pdf",
                sourceLabel: "public-filings",
                documentTitle: "Q4 Report",
                sourceUnit: "KD'000s"
            ),
            page: PageUpsertInput(
                pageNumber: 2,
                ocrVersion: "ocr-v1",
                extractionMethod: "vision_ocr",
                orientationDegrees: 90,
                dpi: 320,
                qualityScore: 0.93,
                confidence: 0.91,
                textContent: "Total Assets: 22,765 KD'000s",
                normalizedTextContent: "Total Assets: 22765000 KWD",
                numericSanityStatus: "repaired"
            ),
            embedding: EmbeddingResult(modelVersion: "embed-v1", vector: [0.1, 0.2, 0.3, 0.4])
        )

        let result = try writer.writeProcessedPage(request)
        #expect(result.documentID > 0)
        #expect(result.pageID > 0)

        #expect(try countRows(dbURL: dbURL, table: "documents") == 1)
        #expect(try countRows(dbURL: dbURL, table: "pages") == 1)
        #expect(try countRows(dbURL: dbURL, table: "page_embeddings") == 1)
    }

    @Test("upsert semantics keep ids stable for idempotency keys")
    func upsertSemanticsKeepIDsStableForIdempotencyKeys() throws {
        let dbURL = temporaryDBURL()
        let writer = try SQLiteStore(databaseURL: dbURL, expectedEmbeddingDimension: 4)

        let request1 = ProcessedPageWriteRequest(
            document: DocumentUpsertInput(sourceSHA256: "sha-2", sourceFilename: "a.pdf", sourceLabel: "batch-a", documentTitle: "A", sourceUnit: "KWD"),
            page: PageUpsertInput(
                pageNumber: 1,
                ocrVersion: "ocr-v2",
                extractionMethod: "text_layer",
                orientationDegrees: 0,
                dpi: 180,
                qualityScore: 0.95,
                confidence: 0.99,
                textContent: "Revenue 120 KWD",
                normalizedTextContent: "Revenue 120 KWD",
                numericSanityStatus: "clean"
            ),
            embedding: EmbeddingResult(modelVersion: "embed-v2", vector: [1, 2, 3, 4])
        )

        let request2 = ProcessedPageWriteRequest(
            document: DocumentUpsertInput(sourceSHA256: "sha-2", sourceFilename: "b.pdf", sourceLabel: "batch-b", documentTitle: "B", sourceUnit: "KWD"),
            page: PageUpsertInput(
                pageNumber: 1,
                ocrVersion: "ocr-v2",
                extractionMethod: "vision_ocr",
                orientationDegrees: 180,
                dpi: 320,
                qualityScore: 0.89,
                confidence: 0.87,
                textContent: "Revenue 121 KWD",
                normalizedTextContent: "Revenue 121 KWD",
                numericSanityStatus: "clean"
            ),
            embedding: EmbeddingResult(modelVersion: "embed-v2", vector: [4, 3, 2, 1])
        )

        let first = try writer.writeProcessedPage(request1)
        let second = try writer.writeProcessedPage(request2)

        #expect(first.documentID == second.documentID)
        #expect(first.pageID == second.pageID)
        #expect(try countRows(dbURL: dbURL, table: "documents") == 1)
        #expect(try countRows(dbURL: dbURL, table: "pages") == 1)
        #expect(try countRows(dbURL: dbURL, table: "page_embeddings") == 1)
    }

    @Test("page schema enforces extraction_method and numeric_sanity_status contract")
    func pageSchemaEnforcesExtractionMethodAndNumericSanityContract() throws {
        let dbURL = temporaryDBURL()
        let writer = try SQLiteStore(databaseURL: dbURL, expectedEmbeddingDimension: 4)

        let badExtraction = ProcessedPageWriteRequest(
            document: DocumentUpsertInput(sourceSHA256: "sha-4", sourceFilename: "d.pdf"),
            page: PageUpsertInput(
                pageNumber: 1,
                ocrVersion: "ocr-v1",
                extractionMethod: "ocr",
                orientationDegrees: 0,
                dpi: 180,
                qualityScore: 0.9,
                confidence: 0.9,
                textContent: "Assets 10",
                numericSanityStatus: "clean"
            ),
            embedding: EmbeddingResult(modelVersion: "embed-v1", vector: [0.1, 0.2, 0.3, 0.4])
        )

        do {
            _ = try writer.writeProcessedPage(badExtraction)
            Issue.record("Expected SQLite CHECK failure for invalid extraction_method")
        } catch SQLiteStoreError.sqlite {
            // expected
        }

        let badSanityStatus = ProcessedPageWriteRequest(
            document: DocumentUpsertInput(sourceSHA256: "sha-5", sourceFilename: "e.pdf"),
            page: PageUpsertInput(
                pageNumber: 1,
                ocrVersion: "ocr-v1",
                extractionMethod: "text_layer",
                orientationDegrees: 0,
                dpi: 180,
                qualityScore: 0.9,
                confidence: 0.9,
                textContent: "Assets 11",
                numericSanityStatus: "unknown"
            ),
            embedding: EmbeddingResult(modelVersion: "embed-v1", vector: [0.1, 0.2, 0.3, 0.4])
        )

        do {
            _ = try writer.writeProcessedPage(badSanityStatus)
            Issue.record("Expected SQLite CHECK failure for invalid numeric_sanity_status")
        } catch SQLiteStoreError.sqlite {
            // expected
        }
    }

    @Test("embedding dimension mismatch blocks persistence")
    func embeddingDimensionMismatchBlocksPersistence() throws {
        let dbURL = temporaryDBURL()
        let writer = try SQLiteStore(databaseURL: dbURL, expectedEmbeddingDimension: 4)

        let request = ProcessedPageWriteRequest(
            document: DocumentUpsertInput(sourceSHA256: "sha-3", sourceFilename: "c.pdf"),
            page: PageUpsertInput(
                pageNumber: 1,
                ocrVersion: "ocr-v1",
                extractionMethod: "text_layer",
                orientationDegrees: 0,
                dpi: 180,
                qualityScore: 0.9,
                confidence: 0.95,
                textContent: "Assets 10",
                numericSanityStatus: "clean"
            ),
            embedding: EmbeddingResult(modelVersion: "embed-v1", vector: [0.1, 0.2, 0.3])
        )

        do {
            _ = try writer.writeProcessedPage(request)
            Issue.record("Expected embedding dimension mismatch")
        } catch SQLiteStoreError.embeddingDimensionMismatch(let expected, let actual) {
            #expect(expected == 4)
            #expect(actual == 3)
        }

        #expect(try countRows(dbURL: dbURL, table: "documents") == 0)
        #expect(try countRows(dbURL: dbURL, table: "pages") == 0)
        #expect(try countRows(dbURL: dbURL, table: "page_embeddings") == 0)
    }
}

private func temporaryDBURL() -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("swift-ingest-store-tests", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appendingPathComponent("\(UUID().uuidString).sqlite")
}

private func countRows(dbURL: URL, table: String) throws -> Int {
    var db: OpaquePointer?
    guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        throw TestError.sqlite("failed to open db")
    }
    defer { sqlite3_close(db) }

    let sql = "SELECT COUNT(*) FROM \(table);"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw TestError.sqlite("failed to prepare query")
    }
    defer { sqlite3_finalize(statement) }

    guard sqlite3_step(statement) == SQLITE_ROW else {
        throw TestError.sqlite("failed to read row count")
    }

    return Int(sqlite3_column_int64(statement, 0))
}

private enum TestError: Error {
    case sqlite(String)
}
