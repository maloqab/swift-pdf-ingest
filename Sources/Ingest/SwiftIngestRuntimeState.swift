import Foundation

public struct SwiftIngestCurrentItem: Codable, Equatable, Sendable {
    public let filePath: String
    public let fileSHA256: String
    public let status: String
    public let startedAt: String
    public let finishedAt: String?
    public let pageCount: Int
    public let chunkCount: Int
    public let errorMessage: String?

    public init(
        filePath: String,
        fileSHA256: String,
        status: String,
        startedAt: String,
        finishedAt: String?,
        pageCount: Int,
        chunkCount: Int,
        errorMessage: String?
    ) {
        self.filePath = filePath
        self.fileSHA256 = fileSHA256
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.pageCount = pageCount
        self.chunkCount = chunkCount
        self.errorMessage = errorMessage
    }

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case fileSHA256 = "file_sha256"
        case status
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case pageCount = "page_count"
        case chunkCount = "chunk_count"
        case errorMessage = "error_message"
    }
}

public struct SwiftIngestRuntimeState: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let processedCount: Int
    public let failedCount: Int
    public let chunkCount: Int
    public let currentItem: SwiftIngestCurrentItem?

    public init(
        generatedAt: String,
        processedCount: Int,
        failedCount: Int,
        chunkCount: Int,
        currentItem: SwiftIngestCurrentItem?
    ) {
        self.generatedAt = generatedAt
        self.processedCount = processedCount
        self.failedCount = failedCount
        self.chunkCount = chunkCount
        self.currentItem = currentItem
    }

    public static func empty(generatedAt: String) -> SwiftIngestRuntimeState {
        SwiftIngestRuntimeState(
            generatedAt: generatedAt,
            processedCount: 0,
            failedCount: 0,
            chunkCount: 0,
            currentItem: nil
        )
    }

    public func statusLine() -> String {
        let currentStatus = currentItem?.status ?? "none"
        let currentPath = currentItem?.filePath ?? ""

        return [
            "swift_ingest_progress",
            "processed=\(processedCount)",
            "failed=\(failedCount)",
            "chunks=\(chunkCount)",
            "generated_at=\(generatedAt)",
            "current_status=\(currentStatus)",
            "current_item=\"\(currentPath)\"",
        ].joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case processedCount = "processed_count"
        case failedCount = "failed_count"
        case chunkCount = "chunk_count"
        case currentItem = "current_item"
    }
}

public enum SwiftIngestRuntimeStateStore {
    public static func read(from url: URL) throws -> SwiftIngestRuntimeState {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty(generatedAt: timestampNowUTC())
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(SwiftIngestRuntimeState.self, from: data)
    }

    public static func write(_ state: SwiftIngestRuntimeState, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)

        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let tmpURL = URL(fileURLWithPath: url.path + ".tmp")
        try data.write(to: tmpURL, options: [.atomic])

        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(
                url,
                withItemAt: tmpURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try FileManager.default.moveItem(at: tmpURL, to: url)
        }

        // replaceItemAt can keep tmp around when target does not yet exist on some file systems.
        if FileManager.default.fileExists(atPath: tmpURL.path) {
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }

    public static func timestampNowUTC() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
}

private func timestampNowUTC() -> String {
    SwiftIngestRuntimeStateStore.timestampNowUTC()
}
