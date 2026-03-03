# Open-Source Transformation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform `swift-pdf-ingest-runtime` into `swift-pdf-ingest` — a general-purpose, open-source Swift PDF ingestion pipeline with pluggable protocols.

**Architecture:** Incremental refactor in place. Extract three protocols (EmbeddingGenerating, StorageWriting, TextExtracting), decouple domain-specific KWD/Arabic logic into an example plugin, rename types for clarity, decompose main.swift, and add open-source scaffolding.

**Tech Stack:** Swift 6.0, PDFKit, Vision framework, SQLite3, swift-testing, GitHub Actions

**Design doc:** `docs/plans/2026-03-03-open-source-transformation-design.md`

---

### Task 1: Verify Baseline

**Files:**
- Read: `Package.swift`

**Step 1: Run all tests to establish green baseline**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && swift test 2>&1`
Expected: All tests pass (EmbeddingWorkerTests, NumericSanityTests, OCRWorkerTests, SwiftIngestRuntimeDecisionsTests, SwiftIngestRuntimeStateTests, TursoWriterTests)

**Step 2: Run build to verify executable compiles**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && swift build --product SwiftIngestRuntime 2>&1`
Expected: Build succeeds

---

### Task 2: Extract StorageWriting Protocol

**Files:**
- Create: `Sources/Ingest/Protocols/StorageWriting.swift`
- Modify: `Sources/Store/TursoWriter.swift`
- Test: `Tests/StoreTests/TursoWriterTests.swift` (verify existing tests still pass)

**Step 1: Create the Protocols directory and StorageWriting protocol**

Create `Sources/Ingest/Protocols/StorageWriting.swift`:

```swift
import Foundation

public struct WriteResult: Sendable, Equatable {
    public let documentID: Int64
    public let pageID: Int64

    public init(documentID: Int64, pageID: Int64) {
        self.documentID = documentID
        self.pageID = pageID
    }
}

public protocol StorageWriting {
    @discardableResult
    func writeProcessedPage(_ request: ProcessedPageWriteRequest) throws -> WriteResult
}
```

Note: `ProcessedPageWriteRequest` already exists in `TursoWriter.swift` and will need to move to this file or stay accessible. Since it's in the `Store` target which depends on `Ingest`, we should move `ProcessedPageWriteRequest`, `DocumentUpsertInput`, and `PageUpsertInput` into the `Ingest` target so the protocol can reference them. These types are pure data — they belong with the protocol.

**Step 2: Move data input types from TursoWriter.swift to a new file in Ingest**

Create `Sources/Ingest/StorageTypes.swift`:

```swift
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
```

Key changes from current:
- `sourceUnit` is now `String?` (was `String` defaulting to `"KWD"`)
- `numericSanityStatus` is now `String?` (was required `String`)

**Step 3: Remove the moved types from TursoWriter.swift**

Remove `DocumentUpsertInput`, `PageUpsertInput`, `ProcessedPageWriteRequest`, and `ProcessedPageWriteResult` from `Sources/Store/TursoWriter.swift`. They now live in `Sources/Ingest/StorageTypes.swift`.

Update `TursoWriter` to conform to `StorageWriting`:

```swift
public final class TursoWriter: StorageWriting {
```

Change the return type of `writeProcessedPage` to return `WriteResult` instead of `ProcessedPageWriteResult` (delete `ProcessedPageWriteResult`):

```swift
@discardableResult
public func writeProcessedPage(_ request: ProcessedPageWriteRequest) throws -> WriteResult {
    // ... existing implementation ...
    return WriteResult(documentID: documentID, pageID: pageID)
}
```

Update the SQL for `sourceUnit` to handle `nil` (bind as NULL instead of requiring a value). Update the SQL for `numericSanityStatus` to default to `"clean"` when `nil`.

**Step 4: Update TursoWriterTests to use WriteResult**

In `Tests/StoreTests/TursoWriterTests.swift`, update any references to `ProcessedPageWriteResult` to use `WriteResult`. Update test `DocumentUpsertInput` constructors — the `sourceUnit` parameter is now `String?`, so existing tests passing `"KWD"` still work.

**Step 5: Run tests to verify**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && swift test 2>&1`
Expected: All tests pass

**Step 6: Commit**

```bash
git add Sources/Ingest/Protocols/StorageWriting.swift Sources/Ingest/StorageTypes.swift Sources/Store/TursoWriter.swift Tests/StoreTests/TursoWriterTests.swift
git commit -m "feat: extract StorageWriting protocol, move data types to Ingest target"
```

---

### Task 3: Extract TextExtracting Protocol

**Files:**
- Create: `Sources/Ingest/Protocols/TextExtracting.swift`
- Modify: `Sources/Ingest/OCRWorker.swift`
- Test: `Tests/IngestTests/OCRWorkerTests.swift` (verify existing tests still pass)

**Step 1: Create the TextExtracting protocol**

Create `Sources/Ingest/Protocols/TextExtracting.swift`:

```swift
import Foundation

public protocol TextExtracting {
    func extract(from page: PDFPagePayload) throws -> ExtractionResult
}

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
```

Note: `ExtractionResult` is a simpler, domain-agnostic version of `OCRWorkerResult`. The `metadata` dictionary replaces the domain-specific fields (`didSweepOrientations`, `didHighDpiRetry`, `didTargetedNumericSecondPass`, `numericReasonCodes`, `sourceUnit`). `OCRWorkerResult` continues to exist as the internal type used by `OCRWorker`.

**Step 2: Add TextExtracting conformance to OCRWorker**

In `Sources/Ingest/OCRWorker.swift`, add conformance:

```swift
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
```

**Step 3: Run tests to verify**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && swift test 2>&1`
Expected: All tests pass (no existing behavior changed)

**Step 4: Commit**

```bash
git add Sources/Ingest/Protocols/TextExtracting.swift Sources/Ingest/OCRWorker.swift
git commit -m "feat: extract TextExtracting protocol with OCRWorker conformance"
```

---

### Task 4: Generalize OCRWorkerResult — Make sourceUnit a String

**Files:**
- Modify: `Sources/Ingest/OCRWorker.swift` (OCRWorkerResult)
- Modify: `Sources/Ingest/NumericSanity.swift` (SourceCurrencyUnit stays for now)
- Modify: `Sources/SwiftIngestRuntime/main.swift`
- Modify: `Tests/IngestTests/OCRWorkerTests.swift`
- Modify: `Tests/IngestTests/TestDoubles.swift`

**Step 1: Change sourceUnit type in OCRWorkerResult**

In `Sources/Ingest/OCRWorker.swift`, change `OCRWorkerResult.sourceUnit` from `SourceCurrencyUnit` to `String?`:

```swift
public struct OCRWorkerResult {
    // ... existing fields ...
    public let sourceUnit: String?

    public init(
        // ... existing params ...
        sourceUnit: String? = nil
    ) {
        // ...
        self.sourceUnit = sourceUnit
    }
}
```

**Step 2: Update OCRWorker.process() to use String**

In the `process()` method, where it currently calls `NumericSanity.detectSourceUnit()` and assigns to `sourceUnit`, change to:

```swift
sourceUnit: NumericSanity.detectSourceUnit(in: bestCandidate.text).rawValue
```

**Step 3: Update main.swift**

In `Sources/SwiftIngestRuntime/main.swift`:
- In `processTextLayerOnly()`, change `sourceUnit: NumericSanity.detectSourceUnit(in: repairedText)` to `sourceUnit: NumericSanity.detectSourceUnit(in: repairedText).rawValue`
- In the main loop where `sourceUnit` is used for `DocumentUpsertInput`, change `sourceUnit: processResult.sourceUnit.rawValue` to `sourceUnit: processResult.sourceUnit`
- In `DocumentProcessResult`, change `sourceUnit` from `SourceCurrencyUnit` to `String?`

**Step 4: Update test files**

In `Tests/IngestTests/OCRWorkerTests.swift`, update any assertions that check `result.sourceUnit` to compare against `String?` values (e.g., `"KWD"`) instead of `SourceCurrencyUnit.kwd`.

**Step 5: Run tests to verify**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && swift test 2>&1`
Expected: All tests pass

**Step 6: Commit**

```bash
git add Sources/Ingest/OCRWorker.swift Sources/SwiftIngestRuntime/main.swift Tests/IngestTests/OCRWorkerTests.swift
git commit -m "refactor: generalize sourceUnit to String? in OCRWorkerResult"
```

---

### Task 5: Make Language Hints Configurable

**Files:**
- Modify: `Sources/Ingest/PDFExtractor.swift` (PDFPagePayload default, VisionOCRRecognizer default)
- Modify: `Sources/SwiftIngestRuntime/main.swift` (pass language hints from config)

**Step 1: Change PDFPagePayload default language hints to empty**

In `Sources/Ingest/PDFExtractor.swift`, change the `languageHints` default from `["ar", "en"]` to `[]`:

```swift
public init(
    // ...
    languageHints: [String] = [],
    // ...
) { ... }
```

**Step 2: Change VisionOCRRecognizer default recognition languages to platform defaults**

In `Sources/Ingest/PDFExtractor.swift`, change VisionOCRRecognizer init:

```swift
public init(
    recognitionLanguages: [String] = ["en"],
    // ...
) { ... }
```

Default to `["en"]` — a sensible global default. Users pass their own languages.

**Step 3: Update main.swift to accept --languages flag**

In `Sources/SwiftIngestRuntime/main.swift`, add `languages: [String]` to `RuntimeConfig` with default `["en"]`, and a `--languages` CLI argument that accepts a comma-separated list. Pass this through to `PDFPagePayload` construction and `VisionOCRRecognizer` init.

**Step 4: Run tests to verify**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && swift test 2>&1`
Expected: All tests pass (tests construct `PDFPagePayload` explicitly so defaults don't affect them)

**Step 5: Commit**

```bash
git add Sources/Ingest/PDFExtractor.swift Sources/SwiftIngestRuntime/main.swift
git commit -m "refactor: make language hints configurable, default to English"
```

---

### Task 6: Split NumericSanity — Keep Generic, Extract KWD/Arabic

**Files:**
- Modify: `Sources/Ingest/NumericSanity.swift` (remove KWD-specific functions)
- Create: `Examples/FinancialArabicPlugin/NumericSanity+Financial.swift`
- Create: `Examples/FinancialArabicPlugin/SourceCurrencyUnit.swift`
- Create: `Examples/FinancialArabicPlugin/README.md`
- Modify: `Sources/Ingest/OCRWorker.swift` (remove detectSourceUnit calls)
- Modify: `Sources/SwiftIngestRuntime/main.swift` (remove detectSourceUnit calls)
- Modify: `Tests/IngestTests/NumericSanityTests.swift` (keep generic tests, move KWD tests)

**Step 1: Identify what stays in core vs. what moves**

**Stays in core** (generic text quality):
- `NumericReasonCode` enum
- `NumericSanityReport` struct
- `NumericSanity.analyze()` — detects generic issues
- `NumericSanity.repairDigitGlyphConfusions()` — generic glyph repair
- `NumericSanity.groupedNumberFidelityScore()` — generic
- `NumericSanity.decimal(from:)` — generic parsing
- Private helpers: `hasMalformedDecimal`, `hasImpossibleNegativeTotal`, `hasDelimiterCorruption`, `hasDigitGlyphConfusion`, `repairNumericToken`, `mapGlyphsToDigits`, `regex`

**Moves to Examples/FinancialArabicPlugin/**:
- `SourceCurrencyUnit` enum
- `NumericSanity.detectSourceUnit()` — KWD-specific detection
- `NumericSanity.normalizeKWDValue()` — KWD-specific normalization
- `NumericSanity.normalizedKWDValueForChatbot()` — KWD-specific
- Private helpers: `normalizeLatinHint`, `normalizeArabicHint`

**Step 2: Remove moved functions from NumericSanity.swift**

Remove `SourceCurrencyUnit`, `detectSourceUnit()`, `normalizeKWDValue()`, `normalizedKWDValueForChatbot()`, `normalizeLatinHint()`, `normalizeArabicHint()` from `Sources/Ingest/NumericSanity.swift`.

**Step 3: Create Examples/FinancialArabicPlugin/SourceCurrencyUnit.swift**

```swift
public enum SourceCurrencyUnit: String, Sendable {
    case kwd = "KWD"
    case kdThousands = "KD_000"
}
```

**Step 4: Create Examples/FinancialArabicPlugin/NumericSanity+Financial.swift**

Contains the extracted KWD-specific functions as standalone public functions (not extensions on `NumericSanity`, since examples don't import the Ingest module as a dependency):

```swift
import Foundation

/// Detects KWD currency units in Arabic/English financial text.
public func detectFinancialSourceUnit(in text: String) -> SourceCurrencyUnit {
    // ... moved implementation from NumericSanity.detectSourceUnit ...
}

/// Normalizes a decimal value from source unit to base KWD.
public func normalizeKWDValue(_ value: Decimal, sourceUnit: SourceCurrencyUnit) -> Decimal {
    // ... moved implementation ...
}

/// Parses a raw numeric literal from financial text and normalizes to KWD.
public func normalizedKWDValueForChatbot(
    rawNumericLiteral: String,
    sourceTextOrUnitHint: String
) -> Decimal? {
    // ... moved implementation ...
}
```

**Step 5: Create Examples/FinancialArabicPlugin/README.md**

```markdown
# Financial Arabic Plugin

Example domain plugin for `swift-pdf-ingest` showing how to add
domain-specific text repair and validation.

This plugin provides:
- KWD (Kuwaiti Dinar) currency unit detection
- Arabic numeral normalization
- Financial value parsing and normalization

## How to use in your own project

Copy these files into your project and call the functions after text
extraction. For example, after getting an `ExtractionResult` from the
pipeline, run `detectFinancialSourceUnit(in: result.text)` to identify
the currency context.

## Adapting for other domains

Use this plugin as a template. Common adaptations:
- Medical terminology normalization
- Legal citation format repair
- Multi-currency financial pipelines
```

**Step 6: Update OCRWorker.process() — remove detectSourceUnit call**

In `Sources/Ingest/OCRWorker.swift`, the `process()` method calls `NumericSanity.detectSourceUnit()`. Remove this call and set `sourceUnit: nil` in the `OCRWorkerResult` construction.

**Step 7: Update main.swift — remove detectSourceUnit calls**

In `Sources/SwiftIngestRuntime/main.swift`:
- In `processTextLayerOnly()`, remove `sourceUnit: NumericSanity.detectSourceUnit(in: repairedText)` and set `sourceUnit: nil`
- In `DocumentProcessResult`, remove `sourceUnit` field entirely (it was only used to pass through to `DocumentUpsertInput.sourceUnit`, which is now `nil` by default)
- In the main loop, remove references to `processResult.sourceUnit`

**Step 8: Update NumericSanityTests — keep generic, note moved tests**

In `Tests/IngestTests/NumericSanityTests.swift`:
- Keep: `detectsDelimiterCorruption`, `detectsTruncatedGroupedNumerics`, `repairDigitGlyphConfusionsNormalizesTokens`, `groupedNumberFidelityScoring`
- Remove: `normalizeKDThousandsAsciiApostrophe`, `normalizeKDThousandsCurlyApostrophe`, `normalizeArabicThousandUnit` (these test KWD-specific functions that moved)

**Step 9: Run tests to verify**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && swift test 2>&1`
Expected: All remaining tests pass

**Step 10: Commit**

```bash
git add Sources/Ingest/NumericSanity.swift Sources/Ingest/OCRWorker.swift Sources/SwiftIngestRuntime/main.swift Tests/IngestTests/NumericSanityTests.swift Examples/
git commit -m "refactor: extract KWD/Arabic domain logic to Examples/FinancialArabicPlugin"
```

---

### Task 7: Rename TursoWriter to SQLiteStore

**Files:**
- Rename: `Sources/Store/TursoWriter.swift` → `Sources/Store/SQLiteStore.swift`
- Modify: `Sources/Store/SQLiteStore.swift` (class name, error enum)
- Rename: `Tests/StoreTests/TursoWriterTests.swift` → `Tests/StoreTests/SQLiteStoreTests.swift`
- Modify: `Tests/StoreTests/SQLiteStoreTests.swift`
- Modify: `Sources/SwiftIngestRuntime/main.swift`

**Step 1: Rename files**

```bash
cd /Users/jarvisz/swift-pdf-ingest-runtime
git mv Sources/Store/TursoWriter.swift Sources/Store/SQLiteStore.swift
git mv Tests/StoreTests/TursoWriterTests.swift Tests/StoreTests/SQLiteStoreTests.swift
```

**Step 2: Rename types in SQLiteStore.swift**

In `Sources/Store/SQLiteStore.swift`:
- `TursoWriterError` → `SQLiteStoreError`
- `TursoWriter` → `SQLiteStore`
- Update all internal references

**Step 3: Update test file**

In `Tests/StoreTests/SQLiteStoreTests.swift`:
- `TursoWriterTests` → `SQLiteStoreTests`
- `@Suite("TursoWriter")` → `@Suite("SQLiteStore")`
- All `TursoWriter(` → `SQLiteStore(`
- All `TursoWriterError` → `SQLiteStoreError`

**Step 4: Update main.swift**

In `Sources/SwiftIngestRuntime/main.swift`:
- `TursoWriter(` → `SQLiteStore(`

**Step 5: Run tests to verify**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && swift test 2>&1`
Expected: All tests pass

**Step 6: Commit**

```bash
git add -A
git commit -m "refactor: rename TursoWriter to SQLiteStore"
```

---

### Task 8: Rename SwiftIngestRuntime Prefixes to Ingest

**Files:**
- Rename: `Sources/Ingest/SwiftIngestRuntimeDecisions.swift` → `Sources/Ingest/IngestDecisions.swift`
- Rename: `Sources/Ingest/SwiftIngestRuntimeState.swift` → `Sources/Ingest/IngestState.swift`
- Rename: `Tests/IngestTests/SwiftIngestRuntimeDecisionsTests.swift` → `Tests/IngestTests/IngestDecisionsTests.swift`
- Rename: `Tests/IngestTests/SwiftIngestRuntimeStateTests.swift` → `Tests/IngestTests/IngestStateTests.swift`
- Modify: all renamed files (type names)
- Modify: `Sources/SwiftIngestRuntime/main.swift`

**Step 1: Rename files**

```bash
cd /Users/jarvisz/swift-pdf-ingest-runtime
git mv Sources/Ingest/SwiftIngestRuntimeDecisions.swift Sources/Ingest/IngestDecisions.swift
git mv Sources/Ingest/SwiftIngestRuntimeState.swift Sources/Ingest/IngestState.swift
git mv Tests/IngestTests/SwiftIngestRuntimeDecisionsTests.swift Tests/IngestTests/IngestDecisionsTests.swift
git mv Tests/IngestTests/SwiftIngestRuntimeStateTests.swift Tests/IngestTests/IngestStateTests.swift
```

**Step 2: Rename types in source files**

In `Sources/Ingest/IngestDecisions.swift`:
- `SwiftIngestRuntimeDecisions` → `IngestDecisions`

In `Sources/Ingest/IngestState.swift`:
- `SwiftIngestCurrentItem` → `IngestCurrentItem`
- `SwiftIngestRuntimeState` → `IngestState`
- `SwiftIngestRuntimeStateStore` → `IngestStateStore`

**Step 3: Rename types in test files**

In `Tests/IngestTests/IngestDecisionsTests.swift`:
- `SwiftIngestRuntimeDecisionsTests` → `IngestDecisionsTests`
- `@Suite("SwiftIngestRuntimeDecisions")` → `@Suite("IngestDecisions")`
- `SwiftIngestRuntimeDecisions.` → `IngestDecisions.`

In `Tests/IngestTests/IngestStateTests.swift`:
- `SwiftIngestRuntimeStateTests` → `IngestStateTests`
- `@Suite("SwiftIngestRuntimeState")` → `@Suite("IngestState")`
- `SwiftIngestRuntimeStateStore.` → `IngestStateStore.`
- `SwiftIngestRuntimeState(` → `IngestState(`
- `SwiftIngestCurrentItem(` → `IngestCurrentItem(`

**Step 4: Update main.swift**

In `Sources/SwiftIngestRuntime/main.swift`, find-replace:
- `SwiftIngestRuntimeDecisions.` → `IngestDecisions.`
- `SwiftIngestRuntimeState(` → `IngestState(`
- `SwiftIngestRuntimeStateStore.` → `IngestStateStore.`
- `SwiftIngestCurrentItem(` → `IngestCurrentItem(`

**Step 5: Run tests to verify**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && swift test 2>&1`
Expected: All tests pass

**Step 6: Commit**

```bash
git add -A
git commit -m "refactor: rename SwiftIngestRuntime* types to Ingest*"
```

---

### Task 9: Decompose main.swift

**Files:**
- Create: `Sources/SwiftIngestRuntime/RuntimeConfig.swift`
- Create: `Sources/SwiftIngestRuntime/PipelineRunner.swift`
- Modify: `Sources/SwiftIngestRuntime/main.swift` (slim down to entry point)

**Step 1: Extract RuntimeConfig.swift**

Move from `main.swift` to `Sources/SwiftIngestRuntime/RuntimeConfig.swift`:
- `RuntimeConfig` struct (with `parse()` and `printHelp()`)
- `CLIError` struct
- `RuntimeExitCode` enum
- `SourceManifestEntry` struct

Change access from `private` to `internal` (default) so `main.swift` and `PipelineRunner.swift` can use them.

**Step 2: Extract PipelineRunner.swift**

Move from `main.swift` to `Sources/SwiftIngestRuntime/PipelineRunner.swift`:
- `PendingPDF` struct
- `ProcessedPage` struct
- `DocumentProcessResult` struct
- `DocumentProcessingError` enum
- `RuntimeWriteCounters` struct
- `DeterministicEmbeddingGenerator` struct
- Functions: `loadSourceManifest`, `discoverPDFs`, `loadSeenSignatures`, `appendSeenSignature`, `sha256File`, `processPDF`, `processTextLayerOnly`, `computeChunkCount`, `normalizeText`, `numericSanityStatus`
- Platform-gated: `orientationFromPDFRotation`, `render`
- The main orchestration loop — extract as `PipelineRunner.run(config:) -> RuntimeExitCode`

Change access from `private` to `internal`.

**Step 3: Slim down main.swift**

`Sources/SwiftIngestRuntime/main.swift` becomes:

```swift
import Foundation
import Ingest
import Store

do {
    let config = try RuntimeConfig.parse(arguments: Array(CommandLine.arguments.dropFirst()))
    let exitCode = PipelineRunner.run(config: config)
    exit(exitCode.rawValue)
} catch let error as CLIError {
    fputs("pdf-ingest error: \(error)\n", stderr)
    exit(RuntimeExitCode.invalidArguments.rawValue)
} catch {
    fputs("pdf-ingest error: \(error)\n", stderr)
    exit(RuntimeExitCode.runtimeFailure.rawValue)
}
```

**Step 4: Run tests to verify**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && swift test 2>&1`
Expected: All tests pass

**Step 5: Run build to verify executable still compiles**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && swift build --product SwiftIngestRuntime 2>&1`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add Sources/SwiftIngestRuntime/
git commit -m "refactor: decompose main.swift into RuntimeConfig, PipelineRunner, and entry point"
```

---

### Task 10: Update Package.swift — Rename Package and Products

**Files:**
- Modify: `Package.swift`
- Rename: `Sources/SwiftIngestRuntime/` → `Sources/PDFIngest/`

**Step 1: Rename the executable source directory**

```bash
cd /Users/jarvisz/swift-pdf-ingest-runtime
git mv Sources/SwiftIngestRuntime Sources/PDFIngest
```

**Step 2: Update Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-pdf-ingest",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "Ingest", targets: ["Ingest"]),
        .library(name: "Store", targets: ["Store"]),
        .executable(name: "pdf-ingest", targets: ["PDFIngest"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "Ingest",
            path: "Sources/Ingest"
        ),
        .target(
            name: "Store",
            dependencies: ["Ingest"],
            path: "Sources/Store"
        ),
        .executableTarget(
            name: "PDFIngest",
            dependencies: ["Ingest", "Store"],
            path: "Sources/PDFIngest"
        ),
        .testTarget(
            name: "IngestTests",
            dependencies: [
                "Ingest",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/IngestTests"
        ),
        .testTarget(
            name: "StoreTests",
            dependencies: [
                "Store",
                "Ingest",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/StoreTests"
        )
    ]
)
```

**Step 3: Run tests and build to verify**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && swift test 2>&1 && swift build --product pdf-ingest 2>&1`
Expected: All tests pass, build succeeds

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor: rename package to swift-pdf-ingest, executable to pdf-ingest"
```

---

### Task 11: Update SQLite Schema Defaults

**Files:**
- Modify: `docs/sqlite_schema.sql`
- Modify: `Sources/Store/SQLiteStore.swift` (schema in `ensureSchema()`)

**Step 1: Update docs/sqlite_schema.sql**

Change `source_unit TEXT DEFAULT 'KWD'` → `source_unit TEXT` (no default).
Change `numeric_sanity_status` CHECK constraint to allow NULL or remove the constraint since it's now optional.

```sql
CREATE TABLE documents (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_url TEXT,
  source_sha256 TEXT NOT NULL UNIQUE,
  source_filename TEXT,
  source_label TEXT,
  document_title TEXT,
  source_unit TEXT,
  created_at TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP),
  updated_at TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP)
);

CREATE TABLE pages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  document_id INTEGER NOT NULL,
  page_number INTEGER NOT NULL,
  ocr_version TEXT NOT NULL,
  extraction_method TEXT NOT NULL DEFAULT 'text_layer' CHECK (extraction_method IN ('text_layer', 'vision_ocr')),
  orientation_degrees INTEGER NOT NULL,
  dpi INTEGER NOT NULL,
  quality_score REAL NOT NULL,
  confidence REAL,
  text_content TEXT NOT NULL,
  normalized_text_content TEXT,
  numeric_sanity_status TEXT,
  created_at TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP),
  updated_at TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP),
  FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE,
  UNIQUE(document_id, page_number, ocr_version)
);
```

**Step 2: Update ensureSchema() in SQLiteStore.swift**

Match the schema changes — remove `DEFAULT 'KWD'`, remove `CHECK` on `numeric_sanity_status`.

**Step 3: Run tests to verify**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && swift test 2>&1`
Expected: All tests pass

**Step 4: Commit**

```bash
git add docs/sqlite_schema.sql Sources/Store/SQLiteStore.swift
git commit -m "refactor: remove KWD defaults from schema, make numeric_sanity_status optional"
```

---

### Task 12: Update run_ingest.sh

**Files:**
- Modify: `scripts/run_ingest.sh`

**Step 1: Update binary name and add --languages flag**

Change:
- `swift build --product SwiftIngestRuntime` → `swift build --product pdf-ingest`
- `BIN_PATH="${BIN_DIR}/SwiftIngestRuntime"` → `BIN_PATH="${BIN_DIR}/pdf-ingest"`
- `SwiftIngestRuntime binary missing` → `pdf-ingest binary missing`
- Add `LANGUAGES="en"` variable and `--languages` flag passthrough

**Step 2: Run script with --help to verify it builds**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && bash scripts/run_ingest.sh --help 2>&1`
Expected: Usage text printed (may fail on build if not macOS with full toolchain — that's OK)

**Step 3: Commit**

```bash
git add scripts/run_ingest.sh
git commit -m "chore: update run_ingest.sh for renamed binary and languages flag"
```

---

### Task 13: Update Source Manifest Example

**Files:**
- Modify: `examples/source_manifest.json`

**Step 1: Make the example more generic**

Replace the KWD-specific example with generic ones:

```json
{
  "annual_report_2025.pdf": {
    "source_url": "https://example.com/reports/annual-2025.pdf",
    "source_label": "annual-reports",
    "document_title": "Annual Report 2025"
  },
  "user_manual_v3.pdf": {
    "source_url": "https://example.com/docs/manual-v3.pdf",
    "source_label": "documentation",
    "document_title": "User Manual v3"
  }
}
```

**Step 2: Commit**

```bash
git add examples/source_manifest.json
git commit -m "chore: generalize source manifest example"
```

---

### Task 14: Add MIT License

**Files:**
- Create: `LICENSE`

**Step 1: Create LICENSE**

```
MIT License

Copyright (c) 2026 maloqab

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**Step 2: Commit**

```bash
git add LICENSE
git commit -m "chore: add MIT license"
```

---

### Task 15: Add CONTRIBUTING.md

**Files:**
- Create: `CONTRIBUTING.md`

**Step 1: Write CONTRIBUTING.md**

```markdown
# Contributing to swift-pdf-ingest

Thank you for your interest in contributing.

## Getting Started

```bash
git clone https://github.com/maloqab/swift-pdf-ingest.git
cd swift-pdf-ingest
swift test
swift build --product pdf-ingest
```

Requirements: Swift 6.0+, macOS 13+ (full pipeline) or Linux (library modules).

## How to Contribute

### Adding a Storage Backend

1. Create a new file in `Sources/Store/` (e.g., `PostgresStore.swift`)
2. Implement the `StorageWriting` protocol
3. Add tests in `Tests/StoreTests/`
4. Submit a PR

### Adding an Embedding Provider

1. Implement the `EmbeddingGenerating` protocol in your own project or submit as an example
2. If submitting to this repo, add to `Examples/`

### Adding a Domain Plugin

Use `Examples/FinancialArabicPlugin/` as a template:
1. Create a new directory under `Examples/`
2. Add domain-specific text repair, validation, or enrichment logic
3. Include a README explaining the use case
4. Submit a PR

### Bug Fixes and Improvements

1. Open an issue describing the bug or improvement
2. Fork the repo and create a branch
3. Write tests first, then implement
4. Ensure `swift test` passes
5. Submit a PR

## Code Style

- Follow existing conventions in the codebase
- Use Swift Testing framework (`@Test`, `@Suite`) for new tests
- Keep protocol conformances in extensions when adding to existing types

## Reporting Issues

Open an issue on GitHub with:
- What you expected to happen
- What actually happened
- Steps to reproduce
- Swift version and platform
```

**Step 2: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "docs: add CONTRIBUTING.md"
```

---

### Task 16: Add GitHub Actions CI

**Files:**
- Create: `.github/workflows/ci.yml`

**Step 1: Create CI workflow**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test-macos:
    name: Test (macOS)
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.4.app/Contents/Developer
      - name: Build
        run: swift build --product pdf-ingest
      - name: Test
        run: swift test

  build-linux:
    name: Build (Linux)
    runs-on: ubuntu-latest
    container:
      image: swift:6.0
    steps:
      - uses: actions/checkout@v4
      - name: Build libraries
        run: swift build --target Ingest --target Store
      - name: Test libraries
        run: swift test
```

**Step 2: Commit**

```bash
mkdir -p .github/workflows
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions workflow for macOS and Linux"
```

---

### Task 17: Rewrite README

**Files:**
- Modify: `README.md`

**Step 1: Rewrite README.md with performance positioning**

Full replacement — see design doc for messaging. Key sections:

1. **Title + one-liner**: "A Swift-native PDF ingestion pipeline — ~30x faster than Python OCR stacks"
2. **Why swift-pdf-ingest**: speed, accuracy, native frameworks, pluggable
3. **Benchmark table**: per-PDF throughput, corpus time, accuracy, memory
4. **Quick start**: clone, test, build, run
5. **Architecture pipeline**: ASCII diagram (keep from original but simplified)
6. **Pluggable protocols**: EmbeddingGenerating, StorageWriting, TextExtracting — with examples
7. **Repository layout**: updated tree
8. **CLI options**: all flags
9. **Manifest format**: spec with example
10. **Resume and dedup behavior**: existing content, cleaned up
11. **SQLite schema**: reference to docs/sqlite_schema.sql
12. **Domain plugins**: link to Examples/FinancialArabicPlugin/ as template
13. **Platform notes**: macOS full support, Linux library-only
14. **License**: MIT

**Step 2: Run final build to make sure nothing references old names**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && swift build --product pdf-ingest 2>&1`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README with performance positioning and updated architecture"
```

---

### Task 18: Final Verification and Push

**Files:**
- None (verification only)

**Step 1: Run full test suite**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && swift test 2>&1`
Expected: All tests pass

**Step 2: Run build**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && swift build --product pdf-ingest 2>&1`
Expected: Build succeeds

**Step 3: Review git log for clean history**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && git log --oneline`
Expected: Clean sequence of commits matching this plan

**Step 4: Push all changes**

Run: `cd /Users/jarvisz/swift-pdf-ingest-runtime && git push origin main`

**Step 5: Rename GitHub repo (manual or via gh)**

```bash
gh repo rename swift-pdf-ingest
```

**Step 6: Update repo metadata**

```bash
gh repo edit --description "A Swift-native PDF ingestion pipeline — ~30x faster than Python OCR stacks" --add-topic swift --add-topic pdf --add-topic ocr --add-topic sqlite --add-topic ingestion --add-topic pipeline --add-topic vision
```

**Step 7: Make repo public**

```bash
gh repo edit --visibility public
```
