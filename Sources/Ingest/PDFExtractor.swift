import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum PageOrientation: Int, CaseIterable {
    case up = 0
    case right = 90
    case down = 180
    case left = 270
}

public enum OCRSource: String {
    case textLayer = "text_layer"
    case visionOCR = "vision_ocr"
}

public struct PDFPagePayload {
    public let pageID: String
    public let pageNumber: Int
    public let name: String
    public let textLayerText: String?
    public let metadataOrientation: PageOrientation
    public let languageHints: [String]
    #if canImport(CoreGraphics)
    public let renderedImage: CGImage?
    #endif

    #if canImport(CoreGraphics)
    public init(
        pageID: String,
        pageNumber: Int,
        name: String,
        textLayerText: String?,
        metadataOrientation: PageOrientation = .up,
        languageHints: [String] = [],
        renderedImage: CGImage? = nil
    ) {
        self.pageID = pageID
        self.pageNumber = pageNumber
        self.name = name
        self.textLayerText = textLayerText
        self.metadataOrientation = metadataOrientation
        self.languageHints = languageHints
        self.renderedImage = renderedImage
    }
    #else
    public init(
        pageID: String,
        pageNumber: Int,
        name: String,
        textLayerText: String?,
        metadataOrientation: PageOrientation = .up,
        languageHints: [String] = []
    ) {
        self.pageID = pageID
        self.pageNumber = pageNumber
        self.name = name
        self.textLayerText = textLayerText
        self.metadataOrientation = metadataOrientation
        self.languageHints = languageHints
    }
    #endif
}

public struct OCRCandidate {
    public let text: String
    public let confidence: Double
    public let orientation: PageOrientation
    public let dpi: Int
    public let source: OCRSource

    public init(
        text: String,
        confidence: Double,
        orientation: PageOrientation,
        dpi: Int,
        source: OCRSource
    ) {
        self.text = text
        self.confidence = confidence
        self.orientation = orientation
        self.dpi = dpi
        self.source = source
    }
}

public protocol VisionOCRRecognizing {
    func recognize(page: PDFPagePayload, orientation: PageOrientation, dpi: Int) throws -> OCRCandidate
}

public enum OCRQualityEvaluator {
    public static func languageSanity(text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let valid = text.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
            || CharacterSet.whitespacesAndNewlines.contains(scalar)
            || "+-–—()[]{}%.,:;/\\'\"&".unicodeScalars.contains(scalar)
            || (0x0600...0x06FF).contains(Int(scalar.value))
        }.count
        return Double(valid) / Double(text.unicodeScalars.count)
    }

    public static func qualityScore(text: String, confidence: Double, minCharsBaseline: Int) -> Double {
        guard !text.isEmpty else { return 0 }
        let charScore = min(1.0, Double(text.count) / Double(max(minCharsBaseline, 1)))
        let sanity = languageSanity(text: text)
        let clippedConfidence = max(0, min(1, confidence))
        return (charScore * 0.45) + (clippedConfidence * 0.35) + (sanity * 0.20)
    }
}

public final class PDFExtractor {
    public init() {}

    public func extractTextLayer(
        from page: PDFPagePayload,
        assumedConfidence: Double = 0.99,
        baseDPI: Int = 180
    ) -> OCRCandidate? {
        guard let text = page.textLayerText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        return OCRCandidate(
            text: text,
            confidence: assumedConfidence,
            orientation: page.metadataOrientation,
            dpi: baseDPI,
            source: .textLayer
        )
    }
}

#if canImport(Vision)
import Vision
import ImageIO


public enum VisionLanguageCorrectionMode: String {
    case off
    case on
    case auto

    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> VisionLanguageCorrectionMode {
        guard let raw = environment["VISION_LANG_CORRECTION_MODE"]?.lowercased() else {
            return .off
        }
        return VisionLanguageCorrectionMode(rawValue: raw) ?? .off
    }
}

public enum VisionOCRRecognizerError: Error {
    case missingRenderedImage(pageID: String)
}

public final class VisionOCRRecognizer: VisionOCRRecognizing {
    private let recognitionLanguages: [String]
    private let renderReferenceDPI: Int
    private let languageCorrectionMode: VisionLanguageCorrectionMode
    private let allowArabicLanguageCorrection: Bool

    public init(
        recognitionLanguages: [String] = ["en"],
        renderReferenceDPI: Int = 320,
        languageCorrectionMode: VisionLanguageCorrectionMode = VisionLanguageCorrectionMode.fromEnvironment(),
        allowArabicLanguageCorrection: Bool = (ProcessInfo.processInfo.environment["VISION_LANG_CORRECTION_ALLOW_ARABIC"] == "1")
    ) {
        self.recognitionLanguages = recognitionLanguages
        self.renderReferenceDPI = max(72, renderReferenceDPI)
        self.languageCorrectionMode = languageCorrectionMode
        self.allowArabicLanguageCorrection = allowArabicLanguageCorrection
    }

    public func recognize(page: PDFPagePayload, orientation: PageOrientation, dpi: Int) throws -> OCRCandidate {
        guard let image = page.renderedImage else {
            throw VisionOCRRecognizerError.missingRenderedImage(pageID: page.pageID)
        }

        let preparedImage = resample(image: image, requestedDPI: dpi)

        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = recognitionLanguages.isEmpty ? page.languageHints : recognitionLanguages
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = shouldUseLanguageCorrection(for: page)

        let handler = VNImageRequestHandler(
            cgImage: preparedImage,
            orientation: orientation.cgImagePropertyOrientation,
            options: [:]
        )
        try handler.perform([request])

        let observations = request.results ?? []
        let candidates = observations.compactMap { $0.topCandidates(1).first }
        let text = candidates.map(\.string).joined(separator: "\n")
        let confidence: Double
        if candidates.isEmpty {
            confidence = 0
        } else {
            confidence = candidates.map { Double($0.confidence) }.reduce(0, +) / Double(candidates.count)
        }

        return OCRCandidate(
            text: text,
            confidence: confidence,
            orientation: orientation,
            dpi: dpi,
            source: .visionOCR
        )
    }

    private func shouldUseLanguageCorrection(for page: PDFPagePayload) -> Bool {
        switch languageCorrectionMode {
        case .off:
            return false
        case .on:
            return allowArabicLanguageCorrection || !containsArabicHint(in: page.languageHints)
        case .auto:
            return !containsArabicHint(in: page.languageHints)
        }
    }

    private func containsArabicHint(in languageHints: [String]) -> Bool {
        languageHints.contains { hint in
            let normalized = hint.lowercased()
            return normalized == "ar" || normalized.hasPrefix("ar-")
        }
    }

    private func resample(image: CGImage, requestedDPI: Int) -> CGImage {
        let safeDPI = max(72, requestedDPI)
        guard safeDPI != renderReferenceDPI else { return image }

        let scale = CGFloat(safeDPI) / CGFloat(renderReferenceDPI)
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))

        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: image.bitsPerComponent,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: image.bitmapInfo.rawValue
              ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}

private extension PageOrientation {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .right: return .right
        case .down: return .down
        case .left: return .left
        }
    }
}
#endif
