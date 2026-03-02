import Foundation
import Testing
@testable import Ingest

@Suite("OCRWorker")
struct OCRWorkerTests {
    @Test("rotation sweep picks best orientation")
    func rotationSweepPicksBestOrientation() throws {
        let recognizer = MockVisionRecognizer()
        recognizer.register(orientation: .up, dpi: 180, text: "x", confidence: 0.20)
        recognizer.register(orientation: .right, dpi: 180, text: String(repeating: "sample statement value 22,765 KD'000s ", count: 5), confidence: 0.92)
        recognizer.register(orientation: .down, dpi: 180, text: "weak down", confidence: 0.30)
        recognizer.register(orientation: .left, dpi: 180, text: "weak left", confidence: 0.25)

        let worker = OCRWorker(extractor: PDFExtractor(), visionRecognizer: recognizer)
        let page = PDFPagePayload(pageID: "masaken-rotated", pageNumber: 3, name: "masaken", textLayerText: nil, metadataOrientation: .up)

        let result = try worker.process(page: page)

        #expect(result.orientation == .right)
        #expect(result.didSweepOrientations)
        #expect(recognizer.calls.count == 4)
        #expect(result.qualityScore > 0.62)
    }

    @Test("quality gate fail is blocking")
    func qualityGateFailIsBlocking() throws {
        let recognizer = MockVisionRecognizer()
        recognizer.register(orientation: .up, dpi: 180, text: "short", confidence: 0.08)
        recognizer.register(orientation: .right, dpi: 180, text: "tiny", confidence: 0.05)
        recognizer.register(orientation: .down, dpi: 180, text: "bad", confidence: 0.04)
        recognizer.register(orientation: .left, dpi: 180, text: "poor", confidence: 0.06)
        recognizer.register(orientation: .up, dpi: 320, text: "still short", confidence: 0.10)

        let logger = MemoryLogger()
        let worker = OCRWorker(extractor: PDFExtractor(), visionRecognizer: recognizer, logger: logger)
        let page = PDFPagePayload(pageID: "gate-fail", pageNumber: 7, name: "gate-fail", textLayerText: nil, metadataOrientation: .up)

        do {
            _ = try worker.process(page: page)
            Issue.record("Expected quality gate failure")
        } catch OCRWorkerError.qualityGateFailed(let pageID, _, _) {
            #expect(pageID == "gate-fail")
            #expect(logger.records.contains(where: { $0.reasonCode == "quality_gate_failed" }))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("numeric anomaly on text-layer triggers targeted second pass")
    func numericAnomalyOnTextLayerTriggersTargetedSecondPass() throws {
        let recognizer = MockVisionRecognizer()
        recognizer.register(
            orientation: .up,
            dpi: 320,
            text: String(repeating: "Total Assets: 22,765 KD’000s ", count: 6),
            confidence: 0.91
        )

        let logger = MemoryLogger()
        let worker = OCRWorker(extractor: PDFExtractor(), visionRecognizer: recognizer, logger: logger)
        let page = PDFPagePayload(
            pageID: "text-layer-numeric",
            pageNumber: 4,
            name: "text-layer-numeric",
            textLayerText: String(repeating: "Total Assets: - 22,765.4.3 KD'000s ", count: 4),
            metadataOrientation: .up
        )

        let result = try worker.process(page: page)

        #expect(result.didTargetedNumericSecondPass)
        #expect(result.numericReasonCodes.isEmpty)
        #expect(result.sourceUnit == .kdThousands)
        #expect(result.source == .visionOCR)
        #expect(recognizer.calls.count == 1)
        #expect(logger.records.contains(where: { $0.reasonCode == NumericReasonCode.malformedDecimal.rawValue }))
    }

    @Test("numeric repair on OCR path still passes quality gate")
    func numericRepairOnOCRPathStillPassesQualityGate() throws {
        let recognizer = MockVisionRecognizer()
        recognizer.register(orientation: .up, dpi: 180, text: String(repeating: "Total Assets: - 22,765.4.3 KD'000s ", count: 4), confidence: 0.85)
        recognizer.register(orientation: .up, dpi: 320, text: String(repeating: "Total Assets: 22,765 KD'000s ", count: 6), confidence: 0.93)

        let worker = OCRWorker(extractor: PDFExtractor(), visionRecognizer: recognizer)
        let page = PDFPagePayload(pageID: "numeric-ocr", pageNumber: 11, name: "numeric-ocr", textLayerText: nil, metadataOrientation: .up)

        let result = try worker.process(page: page)

        #expect(result.didTargetedNumericSecondPass)
        #expect(result.numericReasonCodes.isEmpty)
        #expect(result.qualityScore >= 0.62)
    }

    @Test("digit glyph confusion triggers targeted second pass and repair")
    func digitGlyphConfusionTriggersSecondPassAndRepair() throws {
        let recognizer = MockVisionRecognizer()
        recognizer.register(
            orientation: .up,
            dpi: 180,
            text: String(repeating: "Revenue 58l,d2 Net (05S,82S) Earnings 2٣8.001 ", count: 8),
            confidence: 0.88
        )
        recognizer.register(
            orientation: .up,
            dpi: 320,
            text: String(repeating: "Revenue 581,623 Net 69,829 Earnings 209,123 ", count: 8),
            confidence: 0.93
        )

        let worker = OCRWorker(extractor: PDFExtractor(), visionRecognizer: recognizer)
        let page = PDFPagePayload(pageID: "glyph-confusion", pageNumber: 10, name: "glyph-confusion", textLayerText: nil, metadataOrientation: .up)

        let result = try worker.process(page: page)

        #expect(result.didTargetedNumericSecondPass)
        #expect(result.numericReasonCodes.isEmpty)
        #expect(result.text.contains("581,623"))
        #expect(result.text.contains("69,829"))
        #expect(result.text.contains("209,123"))
    }


    @Test("run5-like truncated numerics recover with varied retry signals")
    func run5LikeTruncatedNumericsRecoverAfterMultipleTargetedPasses() throws {
        let recognizer = MockVisionRecognizer()
        recognizer.register(
            orientation: .up,
            dpi: 180,
            text: String(repeating: "Revenue 58l,62 Net 69,82 Earnings 209,12 ", count: 8),
            confidence: 0.88
        )
        recognizer.register(
            orientation: .up,
            dpi: 320,
            text: String(repeating: "Revenue 581,62 Net 69,82 Earnings 209,12 ", count: 8),
            confidence: 0.91
        )
        recognizer.register(
            orientation: .right,
            dpi: 390,
            text: String(repeating: "Revenue 581,623 Net 69,829 Earnings 209,123 ", count: 8),
            confidence: 0.92
        )

        var config = OCRWorkerConfig()
        config.maxTargetedNumericRetryPasses = 2

        let worker = OCRWorker(extractor: PDFExtractor(), visionRecognizer: recognizer, config: config)
        let page = PDFPagePayload(pageID: "run5-like", pageNumber: 10, name: "run5-like", textLayerText: nil, metadataOrientation: .right)

        let result = try worker.process(page: page)

        #expect(result.didTargetedNumericSecondPass)
        #expect(result.numericReasonCodes.isEmpty)
        #expect(result.text.contains("581,623"))
        #expect(result.text.contains("69,829"))
        #expect(result.text.contains("209,123"))

        let targetedCalls = recognizer.calls.filter { $0.dpi >= 320 }
        #expect(targetedCalls.count == 2)
        #expect(targetedCalls.contains(where: { $0.orientation == .up && $0.dpi == 320 }))
        #expect(targetedCalls.contains(where: { $0.orientation == .right && $0.dpi == 390 }))
    }

    @Test("persistent suspicious numerics stay suspicious when retries do not improve fidelity")
    func persistentSuspiciousNumericsRemainFlagged() throws {
        let recognizer = MockVisionRecognizer()
        let noisyText = String(repeating: "Revenue 581,62 Net 69,82 Earnings 209,12 ", count: 8)
        recognizer.register(orientation: .up, dpi: 180, text: noisyText, confidence: 0.88)
        recognizer.register(orientation: .up, dpi: 320, text: noisyText, confidence: 0.88)
        recognizer.register(orientation: .right, dpi: 390, text: noisyText, confidence: 0.87)

        var config = OCRWorkerConfig()
        config.maxTargetedNumericRetryPasses = 2

        let worker = OCRWorker(extractor: PDFExtractor(), visionRecognizer: recognizer, config: config)
        let page = PDFPagePayload(pageID: "generic-still-bad", pageNumber: 3, name: "generic.pdf", textLayerText: nil, metadataOrientation: .right)

        let result = try worker.process(page: page)

        #expect(result.didTargetedNumericSecondPass)
        #expect(!result.numericReasonCodes.isEmpty)

        let targetedCalls = recognizer.calls.filter { $0.dpi >= 320 }
        #expect(targetedCalls.count == 2)
        #expect(Set(targetedCalls.map(\.orientation)).count == 2)
        #expect(Set(targetedCalls.map(\.dpi)).count == 2)
    }

    @Test("never fabricates numeric literals that OCR never produced")
    func doesNotFabricateNumericLiterals() throws {
        let recognizer = MockVisionRecognizer()
        let corrupted = String(repeating: "... 358,34 581,62 78,51 ... (281,18) (055,825) ... ((2E) 238,001 ... ", count: 5)
        recognizer.register(orientation: .up, dpi: 180, text: corrupted, confidence: 0.90)
        recognizer.register(orientation: .up, dpi: 320, text: corrupted, confidence: 0.90)
        recognizer.register(orientation: .right, dpi: 390, text: corrupted, confidence: 0.90)

        var config = OCRWorkerConfig()
        config.maxTargetedNumericRetryPasses = 2

        let worker = OCRWorker(extractor: PDFExtractor(), visionRecognizer: recognizer, config: config)
        let page = PDFPagePayload(
            pageID: "generic-page",
            pageNumber: 3,
            name: "generic.pdf",
            textLayerText: nil,
            metadataOrientation: .right
        )

        let result = try worker.process(page: page)

        #expect(!result.text.contains("581,623"))
        #expect(!result.text.contains("69,829"))
        #expect(!result.text.contains("209,123"))
        #expect(!result.numericReasonCodes.isEmpty)
    }

    @Test("known persisted page id is preserved even when page number differs")
    func knownPersistedPageIDIsPreservedWhenPageNumberDiffers() throws {
        let recognizer = MockVisionRecognizer()
        recognizer.register(
            orientation: .up,
            dpi: 320,
            text: String(repeating: "Total Assets: 22,765 KD'000s ", count: 6),
            confidence: 0.92
        )

        let logger = MemoryLogger()
        let worker = OCRWorker(extractor: PDFExtractor(), visionRecognizer: recognizer, logger: logger)
        let page = PDFPagePayload(
            pageID: "external-page-ref-99",
            pageNumber: 12,
            name: "mismatch-known-page-id",
            textLayerText: String(repeating: "Total Assets: - 22,765.4.3 KD'000s ", count: 4),
            metadataOrientation: .up
        )

        _ = try worker.process(page: page, runID: 11, documentID: 17, pageID: 555)

        let numericRecord = try #require(logger.records.first(where: { $0.stage == "numeric_sanity" }))
        #expect(numericRecord.pageID == 555)
        #expect(numericRecord.pageNumber == 12)
        #expect(numericRecord.pageRef == "external-page-ref-99")
    }


}
