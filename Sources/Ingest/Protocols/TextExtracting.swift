import Foundation

/// Domain-agnostic result type for text extraction from a PDF page.
public struct ExtractionResult {
    public let pageID: String
    public let text: String
    public let qualityScore: Double
    public let confidence: Double
    public let orientation: PageOrientation
    public let source: OCRSource
    public let dpi: Int
    public let metadata: [String: String]

    public init(
        pageID: String,
        text: String,
        qualityScore: Double,
        confidence: Double,
        orientation: PageOrientation,
        source: OCRSource,
        dpi: Int,
        metadata: [String: String] = [:]
    ) {
        self.pageID = pageID
        self.text = text
        self.qualityScore = qualityScore
        self.confidence = confidence
        self.orientation = orientation
        self.source = source
        self.dpi = dpi
        self.metadata = metadata
    }
}

/// Protocol for extracting text from a PDF page.
///
/// Implement this protocol to provide a clean, domain-agnostic interface
/// for text extraction. The `metadata` dictionary on `ExtractionResult`
/// absorbs any domain-specific fields so the protocol stays generic.
public protocol TextExtracting {
    func extract(from page: PDFPagePayload) throws -> ExtractionResult
}
