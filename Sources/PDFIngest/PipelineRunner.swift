import Crypto
import Foundation
import Ingest
import Store

#if canImport(PDFKit)
import PDFKit
#endif

#if canImport(AppKit)
import AppKit
#endif

struct PendingPDF {
    let url: URL
    let sha256: String

    var signature: String {
        "\(sha256) \(url.path)"
    }
}

struct ProcessedPage {
    let pageNumber: Int
    let result: OCRWorkerResult
}

struct DocumentProcessResult {
    let pageCount: Int
    let chunkCount: Int
    let pages: [ProcessedPage]
    let failedPages: [Int]
    let sourceUnit: String?
}

enum DocumentProcessingError: Error {
    case allPagesFailed(fileName: String, failedPages: [Int])
}

struct RuntimeWriteCounters {
    var documentsDelta = 0
    var pagesDelta = 0
    var embeddingsDelta = 0
}

struct DeterministicEmbeddingGenerator: EmbeddingGenerating {
    let dimension: Int

    func embed(text: String) throws -> [Float] {
        var vector = Array(repeating: Float(0), count: max(1, dimension))
        let bytes = Array(text.utf8)
        if bytes.isEmpty {
            return vector
        }

        for (index, byte) in bytes.enumerated() {
            let slot = index % vector.count
            let centered = Float(Int(byte) - 127) / 127.0
            vector[slot] += centered
        }

        let scale = 1.0 / Float(max(bytes.count, 1))
        for i in vector.indices {
            vector[i] *= scale
        }

        if vector.allSatisfy({ $0 == 0 }) {
            vector[0] = 1.0
        }

        return vector
    }
}

func loadSourceManifest(path: URL?) throws -> [String: SourceManifestEntry] {
    guard let path else { return [:] }
    guard FileManager.default.fileExists(atPath: path.path) else {
        throw CLIError("source manifest not found at \(path.path)")
    }

    let data = try Data(contentsOf: path)
    let decoder = JSONDecoder()
    return try decoder.decode([String: SourceManifestEntry].self, from: data)
}

func discoverPDFs(in inboxDir: URL) throws -> [PendingPDF] {
    let urls = try FileManager.default.contentsOfDirectory(
        at: inboxDir,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )
    return try urls
        .filter { $0.pathExtension.lowercased() == "pdf" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { url in
            PendingPDF(url: url, sha256: try sha256File(url: url))
        }
}

func loadSeenSignatures(from seenFile: URL) throws -> Set<String> {
    guard FileManager.default.fileExists(atPath: seenFile.path) else {
        return []
    }
    let text = try String(contentsOf: seenFile, encoding: .utf8)
    let lines = text.split(whereSeparator: \.isNewline).map { String($0) }
    return Set(lines)
}

func appendSeenSignature(_ signature: String, to seenFile: URL) throws {
    let parent = seenFile.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

    let line = "\(signature)\n"
    if FileManager.default.fileExists(atPath: seenFile.path) {
        let handle = try FileHandle(forWritingTo: seenFile)
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let data = line.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    } else {
        try line.write(to: seenFile, atomically: true, encoding: .utf8)
    }
}

func sha256File(url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func processPDF(url: URL, enableOCRFallback: Bool, languages: [String]) throws -> DocumentProcessResult {
    #if canImport(PDFKit)
    guard let document = PDFDocument(url: url) else {
        throw CLIError("failed to open PDF: \(url.path)")
    }
    guard document.pageCount > 0 else {
        throw CLIError("empty PDF: \(url.path)")
    }

    let worker: OCRWorker?
    if enableOCRFallback {
        #if canImport(Vision)
        var workerConfig = OCRWorkerConfig()
        workerConfig.minCharactersPerPage = 40
        workerConfig.minConfidence = 0.20
        workerConfig.minLanguageSanity = 0.40
        workerConfig.minQualityScore = 0.45
        workerConfig.sweepTriggerQuality = 0.60

        worker = OCRWorker(
            extractor: PDFExtractor(),
            visionRecognizer: VisionOCRRecognizer(recognitionLanguages: languages),
            config: workerConfig
        )
        #else
        throw CLIError("--ocr-fallback requires Vision support on this platform")
        #endif
    } else {
        worker = nil
    }

    var pagesProcessed = 0
    var chunks = 0
    var pages: [ProcessedPage] = []
    var failedPages: [Int] = []
    var sourceUnit: String? = nil

    for pageNumber in 0..<document.pageCount {
        guard let page = document.page(at: pageNumber) else {
            continue
        }

        let payload = PDFPagePayload(
            pageID: "\(url.lastPathComponent)-\(pageNumber + 1)",
            pageNumber: pageNumber + 1,
            name: url.lastPathComponent,
            textLayerText: page.string,
            metadataOrientation: orientationFromPDFRotation(page.rotation),
            languageHints: languages,
            renderedImage: enableOCRFallback ? render(page: page, dpi: 320) : nil
        )

        do {
            let result: OCRWorkerResult
            if let worker {
                result = try worker.process(page: payload)
            } else {
                result = try processTextLayerOnly(page: payload)
            }

            pagesProcessed += 1
            chunks += computeChunkCount(for: result.text)
            sourceUnit = result.sourceUnit
            pages.append(ProcessedPage(pageNumber: pageNumber + 1, result: result))
        } catch {
            failedPages.append(pageNumber + 1)
            continue
        }
    }

    guard pagesProcessed > 0 else {
        throw DocumentProcessingError.allPagesFailed(fileName: url.lastPathComponent, failedPages: failedPages)
    }

    return DocumentProcessResult(
        pageCount: pagesProcessed,
        chunkCount: chunks,
        pages: pages,
        failedPages: failedPages,
        sourceUnit: sourceUnit
    )
    #else
    throw CLIError("SwiftIngestRuntime requires PDFKit support on this platform")
    #endif
}

func processTextLayerOnly(page: PDFPagePayload) throws -> OCRWorkerResult {
    guard let candidate = PDFExtractor().extractTextLayer(from: page) else {
        throw CLIError("missing text layer for page \(page.pageNumber)")
    }

    let repairedText = NumericSanity.repairDigitGlyphConfusions(in: candidate.text)
    let report = NumericSanity.analyze(text: repairedText)
    let quality = OCRQualityEvaluator.qualityScore(
        text: repairedText,
        confidence: candidate.confidence,
        minCharsBaseline: 40
    )

    return OCRWorkerResult(
        pageID: page.pageID,
        text: repairedText,
        qualityScore: quality,
        confidence: candidate.confidence,
        orientation: candidate.orientation,
        source: .textLayer,
        dpi: candidate.dpi,
        didSweepOrientations: false,
        didHighDpiRetry: false,
        didTargetedNumericSecondPass: false,
        numericReasonCodes: report.reasonCodes,
        sourceUnit: nil
    )
}

func computeChunkCount(for text: String, chunkSize: Int = 1200) -> Int {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return 0 }

    var chunks = 0
    var current = 0
    for scalar in normalized.unicodeScalars {
        current += scalar.utf8.count
        if current >= chunkSize {
            chunks += 1
            current = 0
        }
    }
    if current > 0 {
        chunks += 1
    }
    return chunks
}

func normalizeText(_ text: String) -> String {
    let collapsed = text
        .replacingOccurrences(of: "\r", with: "\n")
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    return collapsed
}

func numericSanityStatus(for result: OCRWorkerResult) -> String {
    if !result.numericReasonCodes.isEmpty {
        return "suspicious"
    }
    if result.didTargetedNumericSecondPass {
        return "repaired"
    }
    return "clean"
}

#if canImport(PDFKit) && canImport(AppKit)
func orientationFromPDFRotation(_ rotation: Int) -> PageOrientation {
    switch ((rotation % 360) + 360) % 360 {
    case 90: return .right
    case 180: return .down
    case 270: return .left
    default: return .up
    }
}

func render(page: PDFPage, dpi: Int) -> CGImage? {
    let bounds = page.bounds(for: .mediaBox)
    let scale = CGFloat(dpi) / 72.0
    let width = max(Int(bounds.width * scale), 1)
    let height = max(Int(bounds.height * scale), 1)

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        return nil
    }

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: scale, y: -scale)
    page.draw(with: .mediaBox, to: context)

    return context.makeImage()
}
#endif

enum PipelineRunner {
    static func run(config: RuntimeConfig) -> RuntimeExitCode {
        do {
            try FileManager.default.createDirectory(at: config.inboxDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: config.stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: config.dbPath.deletingLastPathComponent(), withIntermediateDirectories: true)

            let sourceManifest = try loadSourceManifest(path: config.sourceManifestPath)
            let writer = try SQLiteStore(databaseURL: config.dbPath, expectedEmbeddingDimension: config.embeddingDimension)
            let embeddingWorker = EmbeddingWorker(
                generator: DeterministicEmbeddingGenerator(dimension: config.embeddingDimension),
                expectedDimension: config.embeddingDimension,
                defaultModelVersion: config.embeddingModelVersion
            )

            var state = try IngestStateStore.read(from: config.stateFile)
            var seenSignatures = try loadSeenSignatures(from: config.seenFile)
            let candidates = try discoverPDFs(in: config.inboxDir)

            var processedDelta = 0
            var failedDelta = 0
            var chunksDelta = 0
            var pageFailuresDelta = 0
            var writes = RuntimeWriteCounters()
            var failedPagesByDocument: [String] = []
            let startedAt = Date()

            let pending = candidates.filter { !seenSignatures.contains($0.signature) }
            for item in pending.prefix(config.maxDocumentsPerRun) {
                if let timeoutSeconds = config.timeoutSeconds,
                   Date().timeIntervalSince(startedAt) >= TimeInterval(timeoutSeconds) {
                    break
                }
                var current = IngestCurrentItem(
                    filePath: item.url.path,
                    fileSHA256: item.sha256,
                    status: "in_progress",
                    startedAt: IngestStateStore.timestampNowUTC(),
                    finishedAt: nil,
                    pageCount: 0,
                    chunkCount: 0,
                    errorMessage: nil
                )
                state = IngestState(
                    generatedAt: IngestStateStore.timestampNowUTC(),
                    processedCount: state.processedCount,
                    failedCount: state.failedCount,
                    chunkCount: state.chunkCount,
                    currentItem: current
                )
                try IngestStateStore.write(state, to: config.stateFile)

                do {
                    let processResult = try processPDF(url: item.url, enableOCRFallback: config.enableOCRFallback, languages: config.languages)
                    pageFailuresDelta += processResult.failedPages.count
                    if let failedPagesEntry = IngestDecisions.failedPagesSummaryEntry(
                        filename: item.url.lastPathComponent,
                        failedPages: processResult.failedPages
                    ) {
                        failedPagesByDocument.append(failedPagesEntry)
                    }

                    let sourceEntry = sourceManifest[item.url.lastPathComponent]
                    let sourceLabel = sourceEntry?.sourceLabel
                    let documentTitle = sourceEntry?.documentTitle ?? item.url.lastPathComponent

                    let documentInput = DocumentUpsertInput(
                        sourceSHA256: item.sha256,
                        sourceURL: sourceEntry?.sourceURL,
                        sourceFilename: item.url.lastPathComponent,
                        sourceLabel: sourceLabel,
                        documentTitle: documentTitle,
                        sourceUnit: processResult.sourceUnit
                    )

                    var seenDocument = false
                    for processed in processResult.pages {
                        let text = processed.result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { continue }

                        let embedding = try embeddingWorker.generateEmbedding(
                            for: text,
                            modelVersion: config.embeddingModelVersion
                        )

                        let pageInput = PageUpsertInput(
                            pageNumber: processed.pageNumber,
                            ocrVersion: "swift-vision-runtime-v1",
                            extractionMethod: processed.result.source.rawValue,
                            orientationDegrees: processed.result.orientation.rawValue,
                            dpi: processed.result.dpi,
                            qualityScore: processed.result.qualityScore,
                            confidence: processed.result.confidence,
                            textContent: text,
                            normalizedTextContent: normalizeText(text),
                            numericSanityStatus: numericSanityStatus(for: processed.result)
                        )

                        _ = try writer.writeProcessedPage(
                            ProcessedPageWriteRequest(
                                document: documentInput,
                                page: pageInput,
                                embedding: embedding
                            )
                        )

                        if !seenDocument {
                            writes.documentsDelta += 1
                            seenDocument = true
                        }
                        writes.pagesDelta += 1
                        writes.embeddingsDelta += 1
                    }

                    processedDelta += 1
                    chunksDelta += processResult.chunkCount
                    current = IngestCurrentItem(
                        filePath: item.url.path,
                        fileSHA256: item.sha256,
                        status: "processed",
                        startedAt: current.startedAt,
                        finishedAt: IngestStateStore.timestampNowUTC(),
                        pageCount: processResult.pageCount,
                        chunkCount: processResult.chunkCount,
                        errorMessage: nil
                    )
                    state = IngestState(
                        generatedAt: IngestStateStore.timestampNowUTC(),
                        processedCount: state.processedCount + 1,
                        failedCount: state.failedCount,
                        chunkCount: state.chunkCount + processResult.chunkCount,
                        currentItem: current
                    )
                } catch {
                    failedDelta += 1

                    var failedPagesForDocument: [Int] = []
                    if case let DocumentProcessingError.allPagesFailed(_, failedPages) = error {
                        failedPagesForDocument = failedPages
                        pageFailuresDelta += failedPages.count
                        if let failedPagesEntry = IngestDecisions.failedPagesSummaryEntry(
                            filename: item.url.lastPathComponent,
                            failedPages: failedPages
                        ) {
                            failedPagesByDocument.append(failedPagesEntry)
                        }
                    }

                    let baseErrorMessage = String(describing: error)
                    let errorMessage: String
                    if failedPagesForDocument.isEmpty {
                        errorMessage = baseErrorMessage
                    } else {
                        errorMessage = "\(baseErrorMessage) failed_pages=\(failedPagesForDocument.count)"
                    }

                    current = IngestCurrentItem(
                        filePath: item.url.path,
                        fileSHA256: item.sha256,
                        status: "failed",
                        startedAt: current.startedAt,
                        finishedAt: IngestStateStore.timestampNowUTC(),
                        pageCount: 0,
                        chunkCount: 0,
                        errorMessage: errorMessage
                    )
                    state = IngestState(
                        generatedAt: IngestStateStore.timestampNowUTC(),
                        processedCount: state.processedCount,
                        failedCount: state.failedCount + 1,
                        chunkCount: state.chunkCount,
                        currentItem: current
                    )
                }

                if IngestDecisions.shouldAppendSeenSignature(forStatus: current.status) {
                    seenSignatures.insert(item.signature)
                    try appendSeenSignature(item.signature, to: config.seenFile)
                }
                try IngestStateStore.write(state, to: config.stateFile)
            }

            if pending.isEmpty {
                state = IngestState(
                    generatedAt: IngestStateStore.timestampNowUTC(),
                    processedCount: state.processedCount,
                    failedCount: state.failedCount,
                    chunkCount: state.chunkCount,
                    currentItem: state.currentItem
                )
                try IngestStateStore.write(state, to: config.stateFile)
            }

            let currentStatus = state.currentItem?.status ?? "none"
            let currentItemPath = state.currentItem?.filePath ?? ""
            let failedPagesSummary = failedPagesByDocument.isEmpty ? "-" : failedPagesByDocument.joined(separator: ",")
            print(
                "swift_ingest_run "
                    + "processed_delta=\(processedDelta) "
                    + "failed_delta=\(failedDelta) "
                    + "chunks_delta=\(chunksDelta) "
                    + "page_failures_delta=\(pageFailuresDelta) "
                    + "documents_written_delta=\(writes.documentsDelta) "
                    + "pages_written_delta=\(writes.pagesDelta) "
                    + "embeddings_written_delta=\(writes.embeddingsDelta) "
                    + "total_processed=\(state.processedCount) "
                    + "total_failed=\(state.failedCount) "
                    + "total_chunks=\(state.chunkCount) "
                    + "current_status=\(currentStatus) "
                    + "current_item=\"\(currentItemPath)\" "
                    + "failed_pages=\"\(failedPagesSummary)\" "
                    + "db_path=\"\(config.dbPath.path)\""
            )

            return .success
        } catch {
            fputs("SwiftIngestRuntime error: \(error)\n", stderr)
            return .runtimeFailure
        }
    }
}
