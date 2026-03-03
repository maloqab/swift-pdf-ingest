import Foundation

/// Result returned after successfully writing a processed page to storage.
public struct WriteResult: Sendable, Equatable {
    public let documentID: Int64
    public let pageID: Int64

    public init(documentID: Int64, pageID: Int64) {
        self.documentID = documentID
        self.pageID = pageID
    }
}

/// Protocol for writing processed pages to a storage backend.
///
/// Implement this protocol to provide a custom storage backend (e.g., SQLite, PostgreSQL, cloud storage).
public protocol StorageWriting {
    @discardableResult
    func writeProcessedPage(_ request: ProcessedPageWriteRequest) throws -> WriteResult
}
