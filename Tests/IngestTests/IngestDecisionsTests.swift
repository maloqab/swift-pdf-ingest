import Testing
@testable import Ingest

@Suite("IngestDecisions")
struct IngestDecisionsTests {
    @Test("seen signature append is allowed only for processed documents")
    func seenAppendDecision() {
        #expect(IngestDecisions.shouldAppendSeenSignature(forStatus: "processed"))
        #expect(!IngestDecisions.shouldAppendSeenSignature(forStatus: "failed"))
        #expect(!IngestDecisions.shouldAppendSeenSignature(forStatus: "in_progress"))
    }

    @Test("failed pages summary includes filename count and page list")
    func failedPagesSummaryFormatting() {
        let formatted = IngestDecisions.failedPagesSummaryEntry(
            filename: "financial_report_q4.pdf",
            failedPages: [2, 5, 9]
        )

        #expect(formatted == "financial_report_q4.pdf:3[2|5|9]")
        #expect(
            IngestDecisions.failedPagesSummaryEntry(
                filename: "financial_report_q4.pdf",
                failedPages: []
            ) == nil
        )
    }
}
