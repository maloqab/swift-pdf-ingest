# swift-pdf-ingest

A Swift-native PDF ingestion pipeline built on **Apple's PDFKit + Vision frameworks** — **~30x faster** than Python OCR stacks, with higher accuracy through multi-pass extraction and quality gates.

> **macOS only.** This project uses Apple-native frameworks (PDFKit, Vision, CoreGraphics) that are not available on Linux or Windows. Requires macOS 13+ and Swift 6.0+.

## Why swift-pdf-ingest?

| | swift-pdf-ingest | Python (pytesseract) |
|---|---|---|
| **Per-PDF throughput** | ~10s | ~300s |
| **1100-doc corpus** | ~3 hours | ~4 days |
| **OCR strategy** | Multi-pass with quality gates | Single-pass |
| **Memory overhead** | Minimal (streaming) | PIL + numpy buffers |

**Why it's faster:** Apple's native PDFKit + Vision framework do the heavy lifting at the OS level. No Python interpreter overhead. No PIL/numpy serialization roundtrips. Compiled Swift performance.

**Why it's more accurate:** Text-layer extraction first, Vision OCR only when quality is weak. Orientation sweeping across 4 rotations. Automatic high-DPI retry. Quality gates reject garbage text before it enters your database.

## Quick Start

```bash
git clone https://github.com/maloqab/swift-pdf-ingest.git
cd swift-pdf-ingest
swift test
swift build --product pdf-ingest
```

Run ingestion:

```bash
./scripts/run_ingest.sh \
  --pdf-dir ./pdfs \
  --manifest ./examples/source_manifest.json \
  --db-path ./data/pipeline.sqlite \
  --max-docs 25 \
  --ocr-fallback on
```

## Architecture

```
PDF directory + source_manifest.json
        |
        v
[Discover + SHA256 dedup]
        |
        v
[Per-page text extraction]         <-- TextExtracting protocol
  - text layer (fast path)
  - Vision OCR fallback (quality-gated)
  - orientation sweep + DPI retry
        |
        v
[Embedding generation]             <-- EmbeddingGenerating protocol
        |
        v
[Storage writer]                   <-- StorageWriting protocol
  - documents / pages / page_embeddings
        |
        v
[State tracking + run summary]
```

Every step is **pluggable via protocols**. Bring your own embedding model, storage backend, or text extraction strategy.

## Pluggable Protocols

### EmbeddingGenerating

```swift
public protocol EmbeddingGenerating {
    func embed(text: String) throws -> [Float]
}
```

Ships with a deterministic placeholder for testing. Implement this to connect OpenAI, Ollama, or any embedding API.

### StorageWriting

```swift
public protocol StorageWriting {
    func writeProcessedPage(_ request: ProcessedPageWriteRequest) throws -> WriteResult
}
```

Default: `SQLiteStore`. Implement this for Postgres, Turso, or any other backend.

### TextExtracting

```swift
public protocol TextExtracting {
    func extract(from page: PDFPagePayload) throws -> ExtractionResult
}
```

Default: `OCRWorker` (multi-pass with Vision OCR). Implement this for custom extraction logic.

## CLI Options

```
pdf-ingest [options]

  --inbox <path>                     PDF input directory (default: runtime/inbox)
  --db-path <path>                   SQLite database path (default: runtime/data/pipeline.sqlite)
  --source-manifest <path>           JSON manifest mapping filenames to metadata
  --max-docs <n>                     Max PDFs per invocation (default: 25)
  --timeout-seconds <n>              Processing deadline in seconds
  --ocr-fallback <on|off>            Vision OCR fallback (default: on)
  --languages <list>                 Comma-separated OCR languages (default: en)
  --embedding-dim <n>                Embedding vector dimension (default: 16)
  --embedding-model-version <name>   Embedding model version label
```

## Manifest Format

```json
{
  "annual_report_2025.pdf": {
    "source_url": "https://example.com/reports/annual-2025.pdf",
    "source_label": "annual-reports",
    "document_title": "Annual Report 2025"
  }
}
```

All fields are optional. Files not in the manifest still get ingested with filename-based titles.

## Resume and Dedup

- Each file gets a signature: `sha256`
- Signatures are appended to a seen-file only after successful processing
- Subsequent runs skip already-processed files automatically
- Runtime state tracks progress for monitoring and recovery

Safe for incremental execution across large backfills.

## Repository Layout

```
Sources/
  Ingest/                   # Core: protocols, OCR worker, extraction, state
    Protocols/              # EmbeddingGenerating, StorageWriting, TextExtracting
  IngestRuntime/            # Shared runtime used by executable targets
  Store/                    # SQLiteStore (default StorageWriting impl)
  PDFIngest/                # CLI executable
Tests/
  IngestTests/
  StoreTests/
  PDFIngestTests/
examples/
  FinancialArabicPlugin/    # Example domain plugin (KWD currency, Arabic numerals)
  source_manifest.json
docs/
  sqlite_schema.sql
scripts/
  run_ingest.sh
```

## Domain Plugins

The core pipeline is domain-agnostic. Domain-specific logic lives in plugins. See `examples/FinancialArabicPlugin/` for a template showing:

- Currency unit detection (KWD)
- Arabic numeral normalization
- Financial value parsing

Use it as a starting point for your own domain — medical terminology, legal citations, multi-currency pipelines, etc.

## SQLite Schema

Three tables, created automatically:

- `documents` — source metadata, SHA256, dedup key
- `pages` — per-page text, OCR quality scores, extraction method
- `page_embeddings` — vectors with model version tracking

Full schema: [`docs/sqlite_schema.sql`](docs/sqlite_schema.sql)

## Requirements

- **macOS 13+** (Ventura or later)
- **Swift 6.0+**
- **Xcode 16+** (or Swift toolchain with PDFKit/Vision support)

This project relies on Apple-native frameworks — **PDFKit** for PDF parsing, **Vision** for OCR, and **CoreGraphics** for image rendering. These frameworks are the core of what makes the pipeline fast and accurate, and they are only available on macOS.

## License

[MIT](LICENSE)
