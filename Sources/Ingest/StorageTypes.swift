import Foundation

public struct DocumentUpsertInput: Sendable {
    public let sourceSHA256: String
    public let sourceURL: String?
    public let sourceFilename: String?
    public let sourceLabel: String?
    public let documentTitle: String?
    public let sourceUnit: String?

    public init(
        sourceSHA256: String,
        sourceURL: String? = nil,
        sourceFilename: String? = nil,
        sourceLabel: String? = nil,
        documentTitle: String? = nil,
        sourceUnit: String? = nil
    ) {
        self.sourceSHA256 = sourceSHA256
        self.sourceURL = sourceURL
        self.sourceFilename = sourceFilename
        self.sourceLabel = sourceLabel
        self.documentTitle = documentTitle
        self.sourceUnit = sourceUnit
    }
}

public struct PageUpsertInput: Sendable {
    public let pageNumber: Int
    public let ocrVersion: String
    public let extractionMethod: String
    public let orientationDegrees: Int
    public let dpi: Int
    public let qualityScore: Double
    public let confidence: Double?
    public let textContent: String
    public let normalizedTextContent: String?
    public let numericSanityStatus: String?

    public init(
        pageNumber: Int,
        ocrVersion: String,
        extractionMethod: String,
        orientationDegrees: Int,
        dpi: Int,
        qualityScore: Double,
        confidence: Double?,
        textContent: String,
        normalizedTextContent: String? = nil,
        numericSanityStatus: String? = nil
    ) {
        self.pageNumber = pageNumber
        self.ocrVersion = ocrVersion
        self.extractionMethod = extractionMethod
        self.orientationDegrees = orientationDegrees
        self.dpi = dpi
        self.qualityScore = qualityScore
        self.confidence = confidence
        self.textContent = textContent
        self.normalizedTextContent = normalizedTextContent
        self.numericSanityStatus = numericSanityStatus
    }
}

public struct ProcessedPageWriteRequest: Sendable {
    public let document: DocumentUpsertInput
    public let page: PageUpsertInput
    public let embedding: EmbeddingResult

    public init(document: DocumentUpsertInput, page: PageUpsertInput, embedding: EmbeddingResult) {
        self.document = document
        self.page = page
        self.embedding = embedding
    }
}
