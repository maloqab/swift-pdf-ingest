import Foundation
import Testing
@testable import Ingest

@Suite("NumericSanity")
struct NumericSanityTests {
    @Test("delimiter corruption detection")
    func detectsDelimiterCorruption() {
        let report = NumericSanity.analyze(text: "Operating income 98,,120 and revenue 10..44")
        #expect(report.reasonCodes.contains(.delimiterCorruption))
    }
    @Test("truncated grouped numerics are flagged as delimiter corruption")
    func detectsTruncatedGroupedNumerics() {
        let report = NumericSanity.analyze(
            text: "IssuerX revenue 581,62 and profit 69,82 while earnings 209,12"
        )
        #expect(report.reasonCodes.contains(.delimiterCorruption))
    }


    @Test("digit-glyph repair normalizes mixed-script numeric tokens")
    func repairDigitGlyphConfusionsNormalizesTokens() {
        let input = "Revenue 58l,d2 Net (05S,82S) Earnings 2\u{0663}8.001"
        let corrected = NumericSanity.repairDigitGlyphConfusions(in: input)

        #expect(corrected.contains("581,62"))
        #expect(corrected.contains("(055,825)"))
        #expect(corrected.contains("238,001"))
    }

    @Test("grouped-number fidelity score prefers complete thousand groups")
    func groupedNumberFidelityScoring() {
        let lowFidelity = NumericSanity.groupedNumberFidelityScore(in: "Revenue 581,62 Net 69,82 Earnings 209,12")
        let highFidelity = NumericSanity.groupedNumberFidelityScore(in: "Revenue 581,623 Net 69,829 Earnings 209,123")

        #expect(highFidelity > lowFidelity)
    }

}
