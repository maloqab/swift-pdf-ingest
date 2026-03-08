import Crypto
import Foundation
import Ingest
import IngestRuntime
import SQLite3
import Vapor

private func sqliteTransient() -> sqlite3_destructor_type {
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

struct UploadForm: Content {
    var file: File
    var documentTitle: String?
    var sourceLabel: String?
    var sourceURL: String?
    var languages: String?
}

struct DocumentListItem: Content {
    let id: Int64
    let sha256: String
    let title: String
    let filename: String
    let sourceLabel: String?
    let sourceURL: String?
    let updatedAt: String
    let pageCount: Int
    let warningPageCount: Int
    let averageQualityScore: Double
}

struct DocumentPagePayload: Content {
    let pageNumber: Int
    let extractionMethod: String
    let orientationDegrees: Int
    let dpi: Int
    let qualityScore: Double
    let confidence: Double?
    let numericSanityStatus: String
    let textContent: String
    let normalizedTextContent: String
}

struct StructuredDocumentPayload: Content {
    let id: Int64
    let sha256: String
    let title: String
    let filename: String
    let sourceURL: String?
    let sourceLabel: String?
    let sourceUnit: String?
    let createdAt: String
    let updatedAt: String
    let pageCount: Int
    let warningPageCount: Int
    let averageQualityScore: Double
    let cleanText: String
    let rawText: String
    let pages: [DocumentPagePayload]
}

struct UploadResponsePayload: Content {
    let ingestStatus: String
    let ingestError: String?
    let wasCached: Bool
    let document: StructuredDocumentPayload
}

enum WebDataError: Error {
    case sqlite(String)
    case databaseClosed
}

final class StructuredStoreReader {
    private let databaseURL: URL

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    func listDocuments(limit: Int) throws -> [DocumentListItem] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
            SELECT
              d.id,
              d.source_sha256,
              COALESCE(d.document_title, d.source_filename, 'Untitled') AS title,
              COALESCE(d.source_filename, ''),
              d.source_label,
              d.source_url,
              d.updated_at,
              COUNT(p.id) AS page_count,
              COALESCE(SUM(CASE WHEN COALESCE(p.numeric_sanity_status, 'clean') != 'clean' THEN 1 ELSE 0 END), 0) AS warning_pages,
              COALESCE(AVG(p.quality_score), 0)
            FROM documents d
            LEFT JOIN pages p ON p.document_id = d.id
            GROUP BY d.id
            ORDER BY d.updated_at DESC, d.id DESC
            LIMIT ?;
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw WebDataError.sqlite(lastSQLiteMessage(db))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_int64(statement, 1, Int64(limit)) == SQLITE_OK else {
            throw WebDataError.sqlite(lastSQLiteMessage(db))
        }

        var items: [DocumentListItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(
                DocumentListItem(
                    id: sqlite3_column_int64(statement, 0),
                    sha256: stringColumn(statement, index: 1) ?? "",
                    title: stringColumn(statement, index: 2) ?? "Untitled",
                    filename: stringColumn(statement, index: 3) ?? "",
                    sourceLabel: stringColumn(statement, index: 4),
                    sourceURL: stringColumn(statement, index: 5),
                    updatedAt: stringColumn(statement, index: 6) ?? "",
                    pageCount: Int(sqlite3_column_int64(statement, 7)),
                    warningPageCount: Int(sqlite3_column_int64(statement, 8)),
                    averageQualityScore: sqlite3_column_double(statement, 9)
                )
            )
        }

        return items
    }

    func fetchDocument(id: Int64) throws -> StructuredDocumentPayload? {
        try fetchDocument(whereClause: "d.id = ?", bind: { statement, db in
            guard sqlite3_bind_int64(statement, 1, id) == SQLITE_OK else {
                throw WebDataError.sqlite(lastSQLiteMessage(db))
            }
        })
    }

    func fetchDocument(sha256: String) throws -> StructuredDocumentPayload? {
        try fetchDocument(whereClause: "d.source_sha256 = ?", bind: { statement, db in
            guard sqlite3_bind_text(statement, 1, sha256, -1, sqliteTransient()) == SQLITE_OK else {
                throw WebDataError.sqlite(lastSQLiteMessage(db))
            }
        })
    }

    private func fetchDocument(
        whereClause: String,
        bind: (_ statement: OpaquePointer?, _ db: OpaquePointer?) throws -> Void
    ) throws -> StructuredDocumentPayload? {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let documentSQL = """
            SELECT
              d.id,
              d.source_sha256,
              COALESCE(d.document_title, d.source_filename, 'Untitled'),
              COALESCE(d.source_filename, ''),
              d.source_url,
              d.source_label,
              d.source_unit,
              d.created_at,
              d.updated_at
            FROM documents d
            WHERE \(whereClause)
            LIMIT 1;
            """

        var documentStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, documentSQL, -1, &documentStatement, nil) == SQLITE_OK else {
            throw WebDataError.sqlite(lastSQLiteMessage(db))
        }
        defer { sqlite3_finalize(documentStatement) }

        try bind(documentStatement, db)

        guard sqlite3_step(documentStatement) == SQLITE_ROW else {
            return nil
        }

        let documentID = sqlite3_column_int64(documentStatement, 0)
        let sha256 = stringColumn(documentStatement, index: 1) ?? ""
        let title = stringColumn(documentStatement, index: 2) ?? "Untitled"
        let filename = stringColumn(documentStatement, index: 3) ?? ""
        let sourceURL = stringColumn(documentStatement, index: 4)
        let sourceLabel = stringColumn(documentStatement, index: 5)
        let sourceUnit = stringColumn(documentStatement, index: 6)
        let createdAt = stringColumn(documentStatement, index: 7) ?? ""
        let updatedAt = stringColumn(documentStatement, index: 8) ?? ""

        let pageSQL = """
            SELECT
              page_number,
              extraction_method,
              orientation_degrees,
              dpi,
              quality_score,
              confidence,
              COALESCE(numeric_sanity_status, 'clean'),
              text_content,
              COALESCE(normalized_text_content, text_content)
            FROM pages
            WHERE document_id = ?
            ORDER BY page_number ASC;
            """

        var pageStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, pageSQL, -1, &pageStatement, nil) == SQLITE_OK else {
            throw WebDataError.sqlite(lastSQLiteMessage(db))
        }
        defer { sqlite3_finalize(pageStatement) }

        guard sqlite3_bind_int64(pageStatement, 1, documentID) == SQLITE_OK else {
            throw WebDataError.sqlite(lastSQLiteMessage(db))
        }

        var pages: [DocumentPagePayload] = []
        while sqlite3_step(pageStatement) == SQLITE_ROW {
            pages.append(
                DocumentPagePayload(
                    pageNumber: Int(sqlite3_column_int64(pageStatement, 0)),
                    extractionMethod: stringColumn(pageStatement, index: 1) ?? "text_layer",
                    orientationDegrees: Int(sqlite3_column_int64(pageStatement, 2)),
                    dpi: Int(sqlite3_column_int64(pageStatement, 3)),
                    qualityScore: sqlite3_column_double(pageStatement, 4),
                    confidence: doubleColumn(pageStatement, index: 5),
                    numericSanityStatus: stringColumn(pageStatement, index: 6) ?? "clean",
                    textContent: stringColumn(pageStatement, index: 7) ?? "",
                    normalizedTextContent: stringColumn(pageStatement, index: 8) ?? ""
                )
            )
        }

        let cleanText = pages
            .map(\.normalizedTextContent)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let rawText = pages
            .map(\.textContent)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let warningCount = pages.filter { $0.numericSanityStatus != "clean" }.count
        let averageQuality = pages.isEmpty ? 0 : pages.map(\.qualityScore).reduce(0, +) / Double(pages.count)

        return StructuredDocumentPayload(
            id: documentID,
            sha256: sha256,
            title: title,
            filename: filename,
            sourceURL: sourceURL,
            sourceLabel: sourceLabel,
            sourceUnit: sourceUnit,
            createdAt: createdAt,
            updatedAt: updatedAt,
            pageCount: pages.count,
            warningPageCount: warningCount,
            averageQualityScore: averageQuality,
            cleanText: cleanText,
            rawText: rawText,
            pages: pages
        )
    }

    private func openDatabase() throws -> OpaquePointer? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return nil
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "failed to open sqlite database"
            sqlite3_close(db)
            throw WebDataError.sqlite(message)
        }
        return db
    }

    private func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let raw = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: raw)
    }

    private func doubleColumn(_ statement: OpaquePointer?, index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_double(statement, index)
    }

    private func lastSQLiteMessage(_ db: OpaquePointer?) -> String {
        guard let db else { return "database closed" }
        return String(cString: sqlite3_errmsg(db))
    }
}

actor IngestionService {
    private let runtimeRoot: URL
    private let databaseURL: URL
    private let sharedSeenFile: URL
    private let reader: StructuredStoreReader

    init(runtimeRoot: URL) {
        self.runtimeRoot = runtimeRoot
        self.databaseURL = runtimeRoot.appendingPathComponent("data/pipeline.sqlite")
        self.sharedSeenFile = runtimeRoot.appendingPathComponent("state/seen-pdfs.txt")
        self.reader = StructuredStoreReader(databaseURL: databaseURL)
    }

    func listDocuments(limit: Int = 30) throws -> [DocumentListItem] {
        try ensureRuntimeDirectories()
        return try reader.listDocuments(limit: limit)
    }

    func fetchDocument(id: Int64) throws -> StructuredDocumentPayload? {
        try ensureRuntimeDirectories()
        return try reader.fetchDocument(id: id)
    }

    func ingest(form: UploadForm) throws -> UploadResponsePayload {
        try ensureRuntimeDirectories()

        let fileData = try validatedPDFData(from: form.file)
        let sha256 = SHA256.hash(data: fileData).map { String(format: "%02x", $0) }.joined()
        let originalFilename = sanitizedPDFFileName(form.file.filename, fallbackSHA: sha256)
        let manifestEntry = SourceManifestEntry(
            sourceURL: blankToNil(form.sourceURL),
            sourceLabel: blankToNil(form.sourceLabel),
            documentTitle: blankToNil(form.documentTitle)
        )

        let seenBefore = (try? loadSeenSignatures(from: sharedSeenFile).contains(sha256)) ?? false
        let sessionRoot = runtimeRoot.appendingPathComponent("sessions/\(UUID().uuidString)", isDirectory: true)
        let inboxDir = sessionRoot.appendingPathComponent("inbox", isDirectory: true)
        let uploadedPDF = inboxDir.appendingPathComponent(originalFilename)
        let stateFile = sessionRoot.appendingPathComponent("state.json")
        let manifestFile = sessionRoot.appendingPathComponent("source_manifest.json")

        try FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true)
        try fileData.write(to: uploadedPDF, options: .atomic)
        try writeManifest(
            entry: manifestEntry,
            filename: originalFilename,
            to: manifestFile
        )

        let config = RuntimeConfig(
            inboxDir: inboxDir,
            seenFile: sharedSeenFile,
            stateFile: stateFile,
            dbPath: databaseURL,
            sourceManifestPath: manifestFile,
            embeddingDimension: 16,
            embeddingModelVersion: "deterministic-hash-v1",
            maxDocumentsPerRun: 1,
            timeoutSeconds: nil,
            enableOCRFallback: true,
            languages: parsedLanguages(form.languages)
        )

        let exitCode = PipelineRunner.run(config: config)
        let state = try? IngestStateStore.read(from: stateFile)
        guard let document = try reader.fetchDocument(sha256: sha256) else {
            if exitCode != .success {
                throw Abort(.internalServerError, reason: state?.currentItem?.errorMessage ?? "Ingestion failed.")
            }
            throw Abort(.internalServerError, reason: "The document did not produce a stored result.")
        }

        let status = inferredStatus(seenBefore: seenBefore, state: state)
        let errorMessage = status == "failed" ? state?.currentItem?.errorMessage : nil

        return UploadResponsePayload(
            ingestStatus: status,
            ingestError: errorMessage,
            wasCached: seenBefore,
            document: document
        )
    }

    private func inferredStatus(seenBefore: Bool, state: IngestState?) -> String {
        if seenBefore {
            return "cached"
        }
        if let status = state?.currentItem?.status {
            return status
        }
        return "processed"
    }

    private func ensureRuntimeDirectories() throws {
        try FileManager.default.createDirectory(at: runtimeRoot.appendingPathComponent("data"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtimeRoot.appendingPathComponent("state"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtimeRoot.appendingPathComponent("sessions"), withIntermediateDirectories: true)
    }

    private func validatedPDFData(from file: File) throws -> Data {
        var buffer = file.data
        guard let data = buffer.readData(length: buffer.readableBytes), !data.isEmpty else {
            throw Abort(.badRequest, reason: "Upload was empty.")
        }
        guard data.starts(with: [0x25, 0x50, 0x44, 0x46]) else {
            throw Abort(.unsupportedMediaType, reason: "The uploaded file is not a valid PDF.")
        }
        return data
    }

    private func writeManifest(entry: SourceManifestEntry, filename: String, to url: URL) throws {
        let manifest = [filename: entry]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    private func blankToNil(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func parsedLanguages(_ value: String?) -> [String] {
        let tokens = value?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        return tokens.isEmpty ? ["en"] : tokens
    }

    private func sanitizedPDFFileName(_ filename: String, fallbackSHA: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let base = stripped.isEmpty ? "upload-\(fallbackSHA.prefix(8)).pdf" : stripped
        if base.lowercased().hasSuffix(".pdf") {
            return base
        }
        return "\(base).pdf"
    }
}

func resourceResponse(_ req: Request, fileName: String, ext: String, contentType: HTTPMediaType) throws -> Response {
    let url = Bundle.module.url(forResource: fileName, withExtension: ext)
        ?? Bundle.module.url(forResource: fileName, withExtension: ext, subdirectory: "Public")
    guard let url else {
        throw Abort(.internalServerError, reason: "Missing frontend asset: \(fileName).\(ext)")
    }
    let data = try Data(contentsOf: url)
    var headers = HTTPHeaders()
    headers.contentType = contentType
    return Response(status: .ok, headers: headers, body: .init(data: data))
}

let app = Application(.development)
let runtimeRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("runtime/web", isDirectory: true)
let service = IngestionService(runtimeRoot: runtimeRoot)

defer { app.shutdown() }

app.http.server.configuration.hostname = "127.0.0.1"
app.http.server.configuration.port = Int(Environment.get("PORT") ?? "8080") ?? 8080

app.get { req async throws -> Response in
    try resourceResponse(req, fileName: "index", ext: "html", contentType: .html)
}

app.get("app.js") { req async throws -> Response in
    try resourceResponse(
        req,
        fileName: "app",
        ext: "js",
        contentType: HTTPMediaType(type: "application", subType: "javascript")
    )
}

app.get("styles.css") { req async throws -> Response in
    try resourceResponse(req, fileName: "styles", ext: "css", contentType: .css)
}

app.get("api", "health") { _ in
    ["ok": true]
}

app.get("api", "documents") { req async throws -> [DocumentListItem] in
    let limit = min(max(Int(req.query["limit"] ?? "20") ?? 20, 1), 100)
    return try await service.listDocuments(limit: limit)
}

app.get("api", "documents", ":id") { req async throws -> StructuredDocumentPayload in
    guard let rawID = req.parameters.get("id"),
          let id = Int64(rawID),
          let document = try await service.fetchDocument(id: id) else {
        throw Abort(.notFound, reason: "Document not found.")
    }
    return document
}

app.on(.POST, "api", "upload", body: .collect(maxSize: "50mb")) { req async throws -> UploadResponsePayload in
    let form = try req.content.decode(UploadForm.self)
    return try await service.ingest(form: form)
}

try app.run()
