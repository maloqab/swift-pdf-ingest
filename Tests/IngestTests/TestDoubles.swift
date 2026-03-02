import Foundation
@testable import Ingest

final class MockVisionRecognizer: VisionOCRRecognizing, @unchecked Sendable {
    struct Call: Equatable {
        let orientation: PageOrientation
        let dpi: Int
    }

    private var responses: [String: OCRCandidate] = [:]
    private(set) var calls: [Call] = []

    func register(orientation: PageOrientation, dpi: Int, text: String, confidence: Double) {
        responses[key(orientation: orientation, dpi: dpi)] = OCRCandidate(
            text: text,
            confidence: confidence,
            orientation: orientation,
            dpi: dpi,
            source: .visionOCR
        )
    }

    func recognize(page: PDFPagePayload, orientation: PageOrientation, dpi: Int) throws -> OCRCandidate {
        calls.append(Call(orientation: orientation, dpi: dpi))
        let lookupKey = key(orientation: orientation, dpi: dpi)

        if let result = responses[lookupKey] {
            return result
        }
        return OCRCandidate(text: "", confidence: 0.01, orientation: orientation, dpi: dpi, source: .visionOCR)
    }

    private func key(orientation: PageOrientation, dpi: Int) -> String {
        "\(orientation.rawValue)-\(dpi)"
    }
}

final class MemoryLogger: IngestErrorLogging, @unchecked Sendable {
    private(set) var records: [IngestErrorRecord] = []

    func log(_ record: IngestErrorRecord) {
        records.append(record)
    }
}
