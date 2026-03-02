import Foundation
import Testing
@testable import Ingest

@Suite("EmbeddingWorker")
struct EmbeddingWorkerTests {
    @Test("generates embedding with expected dimension")
    func generatesEmbeddingWithExpectedDimension() throws {
        let generator = MockEmbeddingGenerator(vector: [0.1, 0.2, 0.3, 0.4])
        let worker = EmbeddingWorker(generator: generator, expectedDimension: 4, defaultModelVersion: "embed-v1")

        let result = try worker.generateEmbedding(for: "Revenue increased")
        #expect(result.modelVersion == "embed-v1")
        #expect(result.dimension == 4)
    }

    @Test("throws on empty input")
    func throwsOnEmptyInput() throws {
        let generator = MockEmbeddingGenerator(vector: [0.1, 0.2, 0.3, 0.4])
        let worker = EmbeddingWorker(generator: generator, expectedDimension: 4, defaultModelVersion: "embed-v1")

        do {
            _ = try worker.generateEmbedding(for: "")
            Issue.record("Expected emptyText error")
        } catch EmbeddingWorkerError.emptyText {
            // expected
        }
    }

    @Test("throws on whitespace-only input")
    func throwsOnWhitespaceOnlyInput() throws {
        let generator = MockEmbeddingGenerator(vector: [0.1, 0.2, 0.3, 0.4])
        let worker = EmbeddingWorker(generator: generator, expectedDimension: 4, defaultModelVersion: "embed-v1")

        do {
            _ = try worker.generateEmbedding(for: "   \n\t  ")
            Issue.record("Expected emptyText for whitespace-only input")
        } catch EmbeddingWorkerError.emptyText {
            // expected
        }
    }

    @Test("throws on NaN vector value")
    func throwsOnNaNVectorValue() throws {
        let generator = MockEmbeddingGenerator(vector: [0.1, .nan, 0.3, 0.4])
        let worker = EmbeddingWorker(generator: generator, expectedDimension: 4, defaultModelVersion: "embed-v1")

        do {
            _ = try worker.generateEmbedding(for: "Revenue increased")
            Issue.record("Expected invalidVectorValue for NaN")
        } catch EmbeddingWorkerError.invalidVectorValue(let index) {
            #expect(index == 1)
        }
    }

    @Test("throws on infinite vector value")
    func throwsOnInfiniteVectorValue() throws {
        let generator = MockEmbeddingGenerator(vector: [0.1, 0.2, .infinity, 0.4])
        let worker = EmbeddingWorker(generator: generator, expectedDimension: 4, defaultModelVersion: "embed-v1")

        do {
            _ = try worker.generateEmbedding(for: "Revenue increased")
            Issue.record("Expected invalidVectorValue for Inf")
        } catch EmbeddingWorkerError.invalidVectorValue(let index) {
            #expect(index == 2)
        }
    }

    @Test("throws on dimension mismatch")
    func throwsOnDimensionMismatch() throws {
        let generator = MockEmbeddingGenerator(vector: [0.1, 0.2])
        let worker = EmbeddingWorker(generator: generator, expectedDimension: 4, defaultModelVersion: "embed-v1")

        do {
            _ = try worker.generateEmbedding(for: "Revenue increased")
            Issue.record("Expected dimension mismatch")
        } catch EmbeddingWorkerError.dimensionMismatch(let expected, let actual) {
            #expect(expected == 4)
            #expect(actual == 2)
        }
    }
}

private final class MockEmbeddingGenerator: EmbeddingGenerating {
    let vector: [Float]
    init(vector: [Float]) { self.vector = vector }

    func embed(text: String) throws -> [Float] {
        vector
    }
}
