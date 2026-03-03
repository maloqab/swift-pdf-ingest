# Open-Source Transformation Design

**Date:** 2026-03-03
**Status:** Approved
**Approach:** Incremental refactor (in-place)

## Goal

Transform `swift-pdf-ingest-runtime` from a private, domain-specific PDF ingestion tool into a general-purpose open-source Swift PDF pipeline. Position it as a fast, accurate alternative to Python OCR stacks (~30x faster, multi-pass accuracy).

## Protocol Layer

Three protocols define the public API — each pipeline step is swappable:

### EmbeddingGenerating (existing, no change)

```swift
public protocol EmbeddingGenerating {
    func embed(text: String) throws -> [Float]
}
```

Ships with a `DeterministicEmbeddingGenerator` placeholder for testing. Users implement the protocol for real models (OpenAI, Ollama, etc.).

### StorageWriting (new)

```swift
public protocol StorageWriting {
    func writeProcessedPage(_ request: ProcessedPageWriteRequest) throws -> WriteResult
    func close() throws
}
```

`SQLiteStore` (renamed from `TursoWriter`) is the default implementation. Users can implement Postgres, Turso, etc.

### TextExtracting (new)

```swift
public protocol TextExtracting {
    func extract(from page: PDFPagePayload) throws -> OCRWorkerResult
}
```

`OCRWorker` conforms to this. Users who want simpler extraction or a different OCR engine provide their own.

## Domain Code Extraction

All KWD/Arabic-specific logic moves out of core:

**Moves to `Examples/FinancialArabicPlugin/`:**
- `NumericSanity` — KWD currency detection, Arabic digit repair, glyph confusion maps
- `SourceCurrencyUnit` enum

**Core changes:**
- `OCRWorkerResult` drops `sourceUnit` or makes it an optional `String`
- `numericReasonCodes` stays as a generic concept, but KWD/Arabic checks aren't built-in
- Language hints become a configurable parameter (no hardcoded `["ar", "en"]`)
- `numericSanityStatus` in page upsert becomes optional

The example serves as a template: "Here's how to add domain-specific text repair and validation."

## Renames

| Current | New |
|---------|-----|
| `SwiftPDFIngestRuntime` (package) | `swift-pdf-ingest` |
| `SwiftIngestRuntime` (executable target) | `PDFIngest` / `pdf-ingest` |
| `TursoWriter` | `SQLiteStore` |
| `SwiftIngestRuntimeState` | `IngestState` |
| `SwiftIngestRuntimeStateStore` | `IngestStateStore` |
| `SwiftIngestRuntimeDecisions` | `IngestDecisions` |
| `SwiftIngestCurrentItem` | `IngestCurrentItem` |

## main.swift Decomposition

Current 450-line `main.swift` splits into:

- `RuntimeConfig.swift` — CLI argument parsing, help text
- `PipelineRunner.swift` — orchestration loop (discover, extract, embed, write)
- `main.swift` — slim entry point (~20 lines: parse config, create runner, run, exit)

## Repository Layout

```
swift-pdf-ingest/
├── Package.swift
├── LICENSE                              # MIT
├── README.md                            # rewritten with performance positioning
├── CONTRIBUTING.md
├── .github/workflows/ci.yml
├── Sources/
│   ├── Ingest/
│   │   ├── Protocols/
│   │   │   ├── EmbeddingGenerating.swift
│   │   │   ├── StorageWriting.swift
│   │   │   └── TextExtracting.swift
│   │   ├── OCRWorker.swift
│   │   ├── PDFExtractor.swift
│   │   ├── IngestDecisions.swift
│   │   ├── IngestState.swift
│   │   └── EmbeddingWorker.swift
│   ├── Store/
│   │   └── SQLiteStore.swift
│   └── PDFIngest/
│       ├── main.swift
│       ├── RuntimeConfig.swift
│       └── PipelineRunner.swift
├── Tests/
│   ├── IngestTests/
│   │   ├── EmbeddingWorkerTests.swift
│   │   ├── OCRWorkerTests.swift
│   │   ├── IngestDecisionsTests.swift
│   │   ├── IngestStateTests.swift
│   │   └── TestDoubles.swift
│   └── StoreTests/
│       └── SQLiteStoreTests.swift
├── Examples/
│   └── FinancialArabicPlugin/
│       ├── NumericSanity.swift
│       ├── SourceCurrencyUnit.swift
│       └── README.md
├── docs/
│   └── sqlite_schema.sql
├── examples/
│   └── source_manifest.json
└── scripts/
    └── run_ingest.sh
```

## Positioning & README

Lead with performance:
- ~30x faster than Python OCR stacks (pytesseract/pdfplumber)
- Multi-pass OCR with quality gates for higher accuracy
- Native PDFKit + Vision framework — no interpreter overhead

Benchmark table:

| Metric | swift-pdf-ingest | Python (pytesseract) |
|--------|------------------|----------------------|
| Per-PDF throughput | ~10s | ~300s |
| 1100-doc corpus | ~3 hours | ~4 days |
| OCR accuracy | Multi-pass + quality gates | Single-pass |
| Memory overhead | Minimal (streaming) | PIL + numpy buffers |

Explain why: compiled Swift, native frameworks, no serialization roundtrips, quality-gated fallback avoids garbage text.

## Open-Source Scaffolding

- **LICENSE:** MIT
- **CONTRIBUTING.md:** How to add storage backends, embedding providers, domain plugins
- **CI:** GitHub Actions — `swift test` on macOS (full pipeline) + Linux (library modules)
- **Repo topics:** `swift`, `pdf`, `ocr`, `sqlite`, `ingestion`, `pipeline`, `vision`
- **Visibility:** Flip from private to public once ready
