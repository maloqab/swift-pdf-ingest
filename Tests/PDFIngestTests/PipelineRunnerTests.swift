import Foundation
import Testing
@testable import Ingest
@testable import IngestRuntime

@Suite("PipelineRunner")
struct PipelineRunnerTests {
    @Test("pending queue skips seen signatures and in-run duplicates")
    func buildPendingQueueSkipsSeenAndDuplicateCandidates() {
        let candidates = [
            PendingPDF(url: URL(fileURLWithPath: "/tmp/inbox/already-seen.pdf"), sha256: "sha-seen"),
            PendingPDF(url: URL(fileURLWithPath: "/tmp/inbox/first-copy.pdf"), sha256: "sha-dup"),
            PendingPDF(url: URL(fileURLWithPath: "/tmp/inbox/second-copy.pdf"), sha256: "sha-dup"),
            PendingPDF(url: URL(fileURLWithPath: "/tmp/inbox/unique.pdf"), sha256: "sha-unique"),
        ]

        let pending = buildPendingQueue(candidates: candidates, seenSignatures: ["sha-seen"])

        #expect(pending.count == 2)
        #expect(pending.map(\.sha256) == ["sha-dup", "sha-unique"])
        #expect(pending.map { $0.url.lastPathComponent } == ["first-copy.pdf", "unique.pdf"])
    }

    @Test("partial documents are not treated as complete")
    func partialDocumentsRemainRetryable() {
        let partial = DocumentProcessResult(
            pageCount: 3,
            chunkCount: 7,
            pages: [],
            failedPages: [2],
            sourceUnit: nil
        )
        let complete = DocumentProcessResult(
            pageCount: 3,
            chunkCount: 7,
            pages: [],
            failedPages: [],
            sourceUnit: nil
        )

        #expect(!didProcessDocumentCompletely(partial))
        #expect(didProcessDocumentCompletely(complete))
        #expect(!IngestDecisions.shouldAppendSeenSignature(forStatus: "failed"))
        #expect(IngestDecisions.shouldAppendSeenSignature(forStatus: "processed"))
    }

    @Test("ocr render dpi preserves the highest retry resolution")
    func ocrRenderDPIUsesHighestRetryResolution() {
        var config = OCRWorkerConfig()
        config.baseDPI = 180
        config.highDPI = 320
        config.maxTargetedNumericRetryDPI = 640
        #expect(ocrRenderDPI(for: config) == 640)

        config.highDPI = 500
        config.maxTargetedNumericRetryDPI = 450
        #expect(ocrRenderDPI(for: config) == 500)
    }
}
