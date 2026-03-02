import Foundation

public protocol EmbeddingGenerating {
    func embed(text: String) throws -> [Float]
}

public struct EmbeddingResult: Sendable, Equatable {
    public let modelVersion: String
    public let vector: [Float]

    public init(modelVersion: String, vector: [Float]) {
        self.modelVersion = modelVersion
        self.vector = vector
    }

    public var dimension: Int { vector.count }
}

public enum EmbeddingWorkerError: Error {
    case emptyText
    case invalidVectorValue(index: Int)
    case dimensionMismatch(expected: Int, actual: Int)
}

public final class EmbeddingWorker {
    private let generator: EmbeddingGenerating
    private let expectedDimension: Int
    private let defaultModelVersion: String

    public init(
        generator: EmbeddingGenerating,
        expectedDimension: Int,
        defaultModelVersion: String
    ) {
        self.generator = generator
        self.expectedDimension = expectedDimension
        self.defaultModelVersion = defaultModelVersion
    }

    public func generateEmbedding(
        for text: String,
        modelVersion: String? = nil
    ) throws -> EmbeddingResult {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw EmbeddingWorkerError.emptyText
        }

        let vector = try generator.embed(text: normalized)
        guard vector.count == expectedDimension else {
            throw EmbeddingWorkerError.dimensionMismatch(expected: expectedDimension, actual: vector.count)
        }

        for (index, value) in vector.enumerated() where !value.isFinite {
            throw EmbeddingWorkerError.invalidVectorValue(index: index)
        }

        return EmbeddingResult(
            modelVersion: modelVersion ?? defaultModelVersion,
            vector: vector
        )
    }
}
