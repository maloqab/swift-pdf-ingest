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
2. If submitting to this repo, add to `examples/`

### Adding a Domain Plugin

Use `examples/FinancialArabicPlugin/` as a template:

1. Create a new directory under `examples/`
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
