import Foundation
import Testing
@testable import Ingest

@Suite("IngestState")
struct IngestStateTests {
    @Test("state store writes atomically and can be read back")
    func stateStoreRoundTrip() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swift-ingest-state-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let stateURL = tmpDir.appendingPathComponent("swift_ingest_state.json")
        let state = IngestState(
            generatedAt: "2026-03-01T00:00:00Z",
            processedCount: 7,
            failedCount: 2,
            chunkCount: 19,
            currentItem: IngestCurrentItem(
                filePath: "/tmp/inbox/101.pdf",
                fileSHA256: "abc123",
                status: "processed",
                startedAt: "2026-03-01T00:00:00Z",
                finishedAt: "2026-03-01T00:00:01Z",
                pageCount: 3,
                chunkCount: 9,
                errorMessage: nil
            )
        )

        try IngestStateStore.write(state, to: stateURL)
        let loaded = try IngestStateStore.read(from: stateURL)

        #expect(loaded == state)
        #expect(FileManager.default.fileExists(atPath: stateURL.path))
        #expect(!FileManager.default.fileExists(atPath: stateURL.path + ".tmp"))
    }

    @Test("summary line includes required counters and current item")
    func summaryLineIncludesCountersAndCurrentItem() {
        let state = IngestState(
            generatedAt: "2026-03-01T00:00:00Z",
            processedCount: 11,
            failedCount: 1,
            chunkCount: 42,
            currentItem: IngestCurrentItem(
                filePath: "/tmp/inbox/108.pdf",
                fileSHA256: "def456",
                status: "processed",
                startedAt: "2026-03-01T00:00:00Z",
                finishedAt: "2026-03-01T00:00:02Z",
                pageCount: 4,
                chunkCount: 12,
                errorMessage: nil
            )
        )

        let line = state.statusLine()

        #expect(line.contains("processed=11"))
        #expect(line.contains("failed=1"))
        #expect(line.contains("chunks=42"))
        #expect(line.contains("current_status=processed"))
        #expect(line.contains("current_item=\"/tmp/inbox/108.pdf\""))
    }
}
