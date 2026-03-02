# Swift PDF Ingest Runtime

A standalone Swift pipeline for ingesting PDF documents into SQLite with OCR fallback, deterministic embeddings, and idempotent upsert behavior.

## Problem solved

Many document pipelines mix source crawling logic with extraction/runtime logic, making reuse difficult. This repository provides a clean ingestion core that only focuses on:

- reading PDFs from a directory
- extracting page text (text-layer first, OCR fallback)
- generating embeddings
- writing normalized document/page/embedding records to SQLite
- resuming safely across repeated runs

## Architecture pipeline

```text
PDF directory + source_manifest.json
        |
        v
[Discover + SHA256 signatures]
        |
        +--> seen-file dedup gate
        |
        v
[Per-page extraction]
  - text layer path
  - Vision OCR fallback path (optional)
  - numeric sanity + repair hints
        |
        v
[Chunk + embedding generation]
        |
        v
[SQLite upsert writer]
  - documents
  - pages
  - page_embeddings
        |
        v
[state + run summary]
```

## Repository layout

```text
Sources/
  Ingest/                 # OCR worker, extraction logic, state/decision helpers
  Store/                  # SQLite writer and schema bootstrap
  SwiftIngestRuntime/     # CLI runtime executable
Tests/
  IngestTests/
  StoreTests/
scripts/
  run_ingest.sh           # generic shell wrapper
examples/
  source_manifest.json
runtime/
  ...                     # created at runtime (state, db, logs)
```

## Prerequisites

- Swift 6.0+
- SQLite3 runtime (standard on macOS, install `libsqlite3-dev` on Linux)

Platform notes:

- *macOS*: full runtime supported (PDFKit + Vision OCR fallback).
- *Linux*: package builds and tests run for shared modules, but full PDF runtime execution requires PDFKit-capable environment.

## Quick start

```bash
git clone <private-repo-url>
cd swift-pdf-ingest-runtime
swift test
swift build --product SwiftIngestRuntime
```

Run ingestion:

```bash
./scripts/run_ingest.sh \
  --pdf-dir ./runtime/inbox \
  --manifest ./examples/source_manifest.json \
  --db-path ./runtime/data/pipeline.sqlite \
  --max-docs 25 \
  --timeout-seconds 1800 \
  --ocr-fallback on
```

## Manifest format spec

The source manifest is a JSON object keyed by PDF filename:

```json
{
  "filename.pdf": {
    "source_url": "https://example.com/file.pdf",
    "source_label": "public-filings",
    "document_title": "Optional human title"
  }
}
```

Fields:

- `source_url` (optional): canonical source URL.
- `source_label` (optional): free-form origin/category label.
- `document_title` (optional): display title used in `documents.document_title`.

If a filename is not present in the manifest, ingestion still succeeds and defaults to filename-based title.

## Config options

`SwiftIngestRuntime` supports:

- `--max-docs <n>`: batch size per invocation
- `--timeout-seconds <n>`: hard stop window for a single run
- `--ocr-fallback <on|off>`: toggle Vision OCR fallback when text layer quality is weak
- `--embedding-dim <n>`: embedding vector dimension
- `--embedding-model-version <name>`: embedding model version label

## Resume and dedup behavior

- Each file receives a signature: `sha256 + absolute_path`.
- Signatures are appended to a seen-file only after successful processing.
- Subsequent runs skip seen signatures automatically.
- Runtime state (`swift_ingest_state.json`) tracks processed/failed/chunk counters and current item metadata.

This enables safe incremental execution for large backfills.

## SQLite schema documentation

Tables created automatically:

- `documents`
- `pages`
- `page_embeddings`

Schema SQL is documented in `docs/sqlite_schema.sql`.

Upsert behavior:

- `documents`: conflict key `source_sha256`
- `pages`: conflict key `(document_id, page_number, ocr_version)`
- `page_embeddings`: conflict key `(page_id, embedding_model_version)`

## Benchmarks

Observed ingest characteristics from production-scale runs:

- corpus size: ~1100 PDFs
- throughput: ~10 seconds per PDF (end-to-end)
- speedup: ~30x faster versus Python-heavy OCR stacks for equivalent workloads

## Use cases

- regulatory and public filings
- contracts and legal packet ingestion
- internal policy/process PDFs
- mixed-language financial document pipelines

## Example validation commands

```bash
swift test
swift build --product SwiftIngestRuntime
./scripts/run_ingest.sh --pdf-dir ./runtime/inbox --manifest ./examples/source_manifest.json --max-docs 5
sqlite3 ./runtime/data/pipeline.sqlite '.tables'
```
