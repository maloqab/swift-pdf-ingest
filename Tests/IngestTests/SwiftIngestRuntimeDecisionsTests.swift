import Testing
@testable import Ingest

@Suite("SwiftIngestRuntimeDecisions")
struct SwiftIngestRuntimeDecisionsTests {
    @Test("seen signature append is allowed only for processed documents")
    func seenAppendDecision() {
        #expect(SwiftIngestRuntimeDecisions.shouldAppendSeenSignature(forStatus: "processed"))
        #expect(!SwiftIngestRuntimeDecisions.shouldAppendSeenSignature(forStatus: "failed"))
        #expect(!SwiftIngestRuntimeDecisions.shouldAppendSeenSignature(forStatus: "in_progress"))
    }

    @Test("failed pages summary includes filename count and page list")
    func failedPagesSummaryFormatting() {
        let formatted = SwiftIngestRuntimeDecisions.failedPagesSummaryEntry(
            filename: "financial_report_q4.pdf",
            failedPages: [2, 5, 9]
        )

        #expect(formatted == "financial_report_q4.pdf:3[2|5|9]")
        #expect(
            SwiftIngestRuntimeDecisions.failedPagesSummaryEntry(
                filename: "financial_report_q4.pdf",
                failedPages: []
            ) == nil
        )
    }
}
