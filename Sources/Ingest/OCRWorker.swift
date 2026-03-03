import Foundation

public enum IngestErrorSeverity: String {
    case info
    case warning
    case error
    case critical
}

public struct IngestErrorRecord {
    public let runID: Int?
    public let documentID: Int?
    public let pageID: Int?
    public let pageRef: String?
    public let pageNumber: Int?
    public let stage: String
    public let severity: IngestErrorSeverity
    public let reasonCode: String
    public let message: String
    public let contextJSON: String?

    public init(
        runID: Int?,
        documentID: Int?,
        pageID: Int?,
        pageRef: String? = nil,
        pageNumber: Int? = nil,
        stage: String,
        severity: IngestErrorSeverity,
        reasonCode: String,
        message: String,
        contextJSON: String? = nil
    ) {
        self.runID = runID
        self.documentID = documentID
        self.pageID = pageID
        self.pageRef = pageRef
        self.pageNumber = pageNumber
        self.stage = stage
        self.severity = severity
        self.reasonCode = reasonCode
        self.message = message
        self.contextJSON = contextJSON
    }
}

public protocol IngestErrorLogging {
    func log(_ record: IngestErrorRecord)
}

public struct NoopIngestErrorLogger: IngestErrorLogging {
    public init() {}
    public func log(_ record: IngestErrorRecord) {}
}

public struct OCRWorkerConfig {
    public var baseDPI: Int = 180
    public var highDPI: Int = 320
    public var minCharactersPerPage: Int = 120
    public var minConfidence: Double = 0.55
    public var minLanguageSanity: Double = 0.58
    public var minQualityScore: Double = 0.62
    public var sweepTriggerQuality: Double = 0.72
    public var maxTargetedNumericRetryPasses: Int = 2
    public var maxTargetedNumericRetryDPI: Int = 640

    public init() {}
}

public struct OCRWorkerResult {
    public let pageID: String
    public let text: String
    public let qualityScore: Double
    public let confidence: Double
    public let orientation: PageOrientation
    public let source: OCRSource
    public let dpi: Int
    public let didSweepOrientations: Bool
    public let didHighDpiRetry: Bool
    public let didTargetedNumericSecondPass: Bool
    public let numericReasonCodes: [NumericReasonCode]
    public let sourceUnit: SourceCurrencyUnit

    public init(
        pageID: String,
        text: String,
        qualityScore: Double,
        confidence: Double,
        orientation: PageOrientation,
        source: OCRSource,
        dpi: Int,
        didSweepOrientations: Bool,
        didHighDpiRetry: Bool,
        didTargetedNumericSecondPass: Bool,
        numericReasonCodes: [NumericReasonCode],
        sourceUnit: SourceCurrencyUnit
    ) {
        self.pageID = pageID
        self.text = text
        self.qualityScore = qualityScore
        self.confidence = confidence
        self.orientation = orientation
        self.source = source
        self.dpi = dpi
        self.didSweepOrientations = didSweepOrientations
        self.didHighDpiRetry = didHighDpiRetry
        self.didTargetedNumericSecondPass = didTargetedNumericSecondPass
        self.numericReasonCodes = numericReasonCodes
        self.sourceUnit = sourceUnit
    }
}

public enum OCRWorkerError: Error {
    case noCandidateProduced(pageID: String)
    case qualityGateFailed(pageID: String, qualityScore: Double, confidence: Double)
}

public final class OCRWorker {
    private let extractor: PDFExtractor
    private let visionRecognizer: VisionOCRRecognizing
    private let logger: IngestErrorLogging
    private let config: OCRWorkerConfig

    public init(
        extractor: PDFExtractor,
        visionRecognizer: VisionOCRRecognizing,
        logger: IngestErrorLogging = NoopIngestErrorLogger(),
        config: OCRWorkerConfig = OCRWorkerConfig()
    ) {
        self.extractor = extractor
        self.visionRecognizer = visionRecognizer
        self.logger = logger
        self.config = config
    }

    public func process(
        page: PDFPagePayload,
        runID: Int? = nil,
        documentID: Int? = nil,
        pageID: Int? = nil
    ) throws -> OCRWorkerResult {
        if let textLayerCandidate = extractor.extractTextLayer(from: page, baseDPI: config.baseDPI), passesQualityGate(textLayerCandidate) {
            let numericResult = try applyNumericSanityAndRepairIfNeeded(
                candidate: textLayerCandidate,
                page: page,
                runID: runID,
                documentID: documentID,
                pageID: pageID
            )

            let selectedCandidate = numericResult.candidate

            try ensureQualityGatePassed(
                selectedCandidate,
                page: page,
                runID: runID,
                documentID: documentID,
                pageID: pageID
            )

            let finalNumericReport = NumericSanity.analyze(text: selectedCandidate.text)

            return OCRWorkerResult(
                pageID: page.pageID,
                text: selectedCandidate.text,
                qualityScore: quality(of: selectedCandidate),
                confidence: selectedCandidate.confidence,
                orientation: selectedCandidate.orientation,
                source: selectedCandidate.source,
                dpi: selectedCandidate.dpi,
                didSweepOrientations: false,
                didHighDpiRetry: selectedCandidate.source == .visionOCR,
                didTargetedNumericSecondPass: numericResult.didSecondPass,
                numericReasonCodes: finalNumericReport.reasonCodes,
                sourceUnit: NumericSanity.detectSourceUnit(in: selectedCandidate.text)
            )
        }

        var didSweep = false
        var didHighDPI = false

        var bestCandidate = try visionRecognizer.recognize(
            page: page,
            orientation: page.metadataOrientation,
            dpi: config.baseDPI
        )

        if quality(of: bestCandidate) < config.sweepTriggerQuality {
            didSweep = true
            for orientation in PageOrientation.allCases where orientation != page.metadataOrientation {
                let candidate = try visionRecognizer.recognize(page: page, orientation: orientation, dpi: config.baseDPI)
                if quality(of: candidate) > quality(of: bestCandidate) {
                    bestCandidate = candidate
                }
            }
        }

        if !passesQualityGate(bestCandidate) {
            let retried = try visionRecognizer.recognize(page: page, orientation: bestCandidate.orientation, dpi: config.highDPI)
            didHighDPI = true
            if quality(of: retried) >= quality(of: bestCandidate) {
                bestCandidate = retried
            }
        }

        let numericResult = try applyNumericSanityAndRepairIfNeeded(
            candidate: bestCandidate,
            page: page,
            runID: runID,
            documentID: documentID,
            pageID: pageID
        )

        let selectedCandidate = numericResult.candidate

        try ensureQualityGatePassed(
            selectedCandidate,
            page: page,
            runID: runID,
            documentID: documentID,
            pageID: pageID
        )

        guard !selectedCandidate.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OCRWorkerError.noCandidateProduced(pageID: page.pageID)
        }

        let finalNumericReport = NumericSanity.analyze(text: selectedCandidate.text)

        return OCRWorkerResult(
            pageID: page.pageID,
            text: selectedCandidate.text,
            qualityScore: quality(of: selectedCandidate),
            confidence: selectedCandidate.confidence,
            orientation: selectedCandidate.orientation,
            source: .visionOCR,
            dpi: selectedCandidate.dpi,
            didSweepOrientations: didSweep,
            didHighDpiRetry: didHighDPI || selectedCandidate.dpi >= config.highDPI,
            didTargetedNumericSecondPass: numericResult.didSecondPass,
            numericReasonCodes: finalNumericReport.reasonCodes,
            sourceUnit: NumericSanity.detectSourceUnit(in: selectedCandidate.text)
        )
    }

    private func applyNumericSanityAndRepairIfNeeded(
        candidate: OCRCandidate,
        page: PDFPagePayload,
        runID: Int?,
        documentID: Int?,
        pageID: Int?
    ) throws -> (candidate: OCRCandidate, didSecondPass: Bool, reasonCodes: [NumericReasonCode]) {
        let repairedInitialCandidate = repairedCandidate(from: candidate)
        let initialReport = NumericSanity.analyze(text: repairedInitialCandidate.text)

        if !initialReport.isSuspicious {
            return (repairedInitialCandidate, false, initialReport.reasonCodes)
        }

        for reason in initialReport.reasonCodes {
            logger.log(
                IngestErrorRecord(
                    runID: runID,
                    documentID: documentID,
                    pageID: pageID,
                    pageRef: page.pageID,
                    pageNumber: page.pageNumber,
                    stage: "numeric_sanity",
                    severity: .warning,
                    reasonCode: reason.rawValue,
                    message: "Numeric sanity issue detected; triggering targeted second-pass OCR"
                )
            )
        }

        var selectedCandidate = repairedInitialCandidate
        var selectedReport = initialReport
        let retryBudget = max(1, config.maxTargetedNumericRetryPasses)
        let retrySignals = targetedRetrySignals(
            seedOrientation: repairedInitialCandidate.orientation,
            metadataOrientation: page.metadataOrientation,
            seedDPI: repairedInitialCandidate.dpi,
            retryCount: retryBudget
        )
        var didSecondPass = false

        for signal in retrySignals {
            didSecondPass = true
            let targetedRetry = try visionRecognizer.recognize(
                page: page,
                orientation: signal.orientation,
                dpi: signal.dpi
            )
            let repairedRetryCandidate = repairedCandidate(from: targetedRetry)
            let retryReport = NumericSanity.analyze(text: repairedRetryCandidate.text)

            if shouldPreferNumericCandidate(
                repairedRetryCandidate,
                report: retryReport,
                over: selectedCandidate,
                currentReport: selectedReport
            ) {
                selectedCandidate = repairedRetryCandidate
                selectedReport = retryReport
            }

            if !selectedReport.isSuspicious {
                break
            }
        }

        return (selectedCandidate, didSecondPass, selectedReport.reasonCodes)
    }

    private func targetedRetrySignals(
        seedOrientation: PageOrientation,
        metadataOrientation: PageOrientation,
        seedDPI: Int,
        retryCount: Int
    ) -> [(orientation: PageOrientation, dpi: Int)] {
        let retries = max(1, retryCount)
        let maxRetryDPI = max(config.highDPI, config.maxTargetedNumericRetryDPI)
        let baseRetryDPI = min(maxRetryDPI, max(config.highDPI, seedDPI))
        let dpiStep = max(40, (config.highDPI - config.baseDPI) / 2)

        var orientationCycle: [PageOrientation] = []
        func appendUnique(_ orientation: PageOrientation) {
            if !orientationCycle.contains(orientation) {
                orientationCycle.append(orientation)
            }
        }

        appendUnique(seedOrientation)
        appendUnique(metadataOrientation)
        appendUnique(rotated(seedOrientation, byQuarterTurns: 1))
        appendUnique(rotated(seedOrientation, byQuarterTurns: 3))
        appendUnique(rotated(seedOrientation, byQuarterTurns: 2))

        var signals: [(orientation: PageOrientation, dpi: Int)] = []
        for retryIndex in 0..<retries {
            let orientation = orientationCycle[retryIndex % orientationCycle.count]
            let dpi = min(maxRetryDPI, baseRetryDPI + (retryIndex * dpiStep))
            signals.append((orientation, dpi))
        }
        return signals
    }

    private func rotated(_ orientation: PageOrientation, byQuarterTurns turns: Int) -> PageOrientation {
        let all: [PageOrientation] = [.up, .right, .down, .left]
        guard let idx = all.firstIndex(of: orientation) else {
            return orientation
        }
        let normalizedTurns = ((turns % all.count) + all.count) % all.count
        return all[(idx + normalizedTurns) % all.count]
    }

    private func shouldPreferNumericCandidate(
        _ candidate: OCRCandidate,
        report: NumericSanityReport,
        over current: OCRCandidate,
        currentReport: NumericSanityReport
    ) -> Bool {
        let candidateTrimmed = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentTrimmed = current.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if candidateTrimmed.isEmpty {
            return false
        }
        if currentTrimmed.isEmpty {
            return true
        }

        let candidateQuality = quality(of: candidate)
        let currentQuality = quality(of: current)
        if candidateQuality + 0.05 < currentQuality {
            return false
        }

        if report.reasonCodes.count != currentReport.reasonCodes.count {
            return report.reasonCodes.count < currentReport.reasonCodes.count
        }

        let candidateFidelity = NumericSanity.groupedNumberFidelityScore(in: candidate.text)
        let currentFidelity = NumericSanity.groupedNumberFidelityScore(in: current.text)
        if candidateFidelity != currentFidelity {
            return candidateFidelity > currentFidelity
        }

        if candidateQuality != currentQuality {
            return candidateQuality > currentQuality
        }

        return candidate.confidence > current.confidence
    }

    private func repairedCandidate(from candidate: OCRCandidate) -> OCRCandidate {
        let repairedText = NumericSanity.repairDigitGlyphConfusions(in: candidate.text)
        guard repairedText != candidate.text else { return candidate }
        return OCRCandidate(
            text: repairedText,
            confidence: candidate.confidence,
            orientation: candidate.orientation,
            dpi: candidate.dpi,
            source: candidate.source
        )
    }

    private func ensureQualityGatePassed(
        _ candidate: OCRCandidate,
        page: PDFPagePayload,
        runID: Int?,
        documentID: Int?,
        pageID: Int?
    ) throws {
        guard passesQualityGate(candidate) else {
            let score = quality(of: candidate)
            logger.log(
                IngestErrorRecord(
                    runID: runID,
                    documentID: documentID,
                    pageID: pageID,
                    pageRef: page.pageID,
                    pageNumber: page.pageNumber,
                    stage: "quality_gate",
                    severity: .error,
                    reasonCode: "quality_gate_failed",
                    message: "Page did not pass OCR quality gate after retries",
                    contextJSON: "{\"quality\":\(score),\"confidence\":\(candidate.confidence),\"page_number\":\(page.pageNumber)}"
                )
            )
            throw OCRWorkerError.qualityGateFailed(pageID: page.pageID, qualityScore: score, confidence: candidate.confidence)
        }
    }

    private func passesQualityGate(_ candidate: OCRCandidate) -> Bool {
        let sanity = OCRQualityEvaluator.languageSanity(text: candidate.text)
        let qualityScore = quality(of: candidate)
        return candidate.text.count >= config.minCharactersPerPage
            && candidate.confidence >= config.minConfidence
            && sanity >= config.minLanguageSanity
            && qualityScore >= config.minQualityScore
    }

    private func quality(of candidate: OCRCandidate) -> Double {
        OCRQualityEvaluator.qualityScore(
            text: candidate.text,
            confidence: candidate.confidence,
            minCharsBaseline: config.minCharactersPerPage
        )
    }
}

extension OCRWorker: TextExtracting {
    public func extract(from page: PDFPagePayload) throws -> ExtractionResult {
        let result = try process(page: page)
        return ExtractionResult(
            pageID: result.pageID,
            text: result.text,
            qualityScore: result.qualityScore,
            confidence: result.confidence,
            orientation: result.orientation,
            source: result.source,
            dpi: result.dpi,
            metadata: [
                "didSweepOrientations": String(result.didSweepOrientations),
                "didHighDpiRetry": String(result.didHighDpiRetry),
                "didTargetedNumericSecondPass": String(result.didTargetedNumericSecondPass),
                "numericReasonCodes": result.numericReasonCodes.map(\.rawValue).joined(separator: ","),
                "sourceUnit": result.sourceUnit.rawValue
            ]
        )
    }
}
