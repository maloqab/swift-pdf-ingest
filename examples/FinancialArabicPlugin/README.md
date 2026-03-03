# FinancialArabicPlugin

Reference code for detecting and normalizing **Kuwaiti-Dinar (KWD)** currency
units in OCR-extracted financial statements, including Arabic-script hints.

## What this is

Many Kuwaiti banks and companies publish financial statements where amounts are
expressed in *thousands* of Kuwaiti Dinars ("KD '000s"). The hint that tells
you the scale factor can appear in Latin script ("KD'000", "KWD 000S") or in
Arabic script ("بالألف د.ك", "الأرقام بالألاف دينار كويتي").

This plugin provides:

| File | Purpose |
|------|---------|
| `SourceCurrencyUnit.swift` | Enum distinguishing raw KWD from KD-thousands |
| `NumericSanity+Financial.swift` | Detection and normalization functions |

## How to use

These files are **standalone** -- they have no dependency on the `Ingest`
module. Copy them into your own Swift project and call the public functions
directly:

```swift
import Foundation

// Detect the unit from a page header
let unit = detectFinancialSourceUnit(in: pageHeaderText)

// Scale a parsed value
let fullKWD = normalizeKWDValue(parsedDecimal, sourceUnit: unit)

// Or do it all in one shot for a chatbot pipeline
if let value = normalizedKWDValueForChatbot(
    rawNumericLiteral: "22,765",
    sourceTextOrUnitHint: "KD'000s"
) {
    print(value) // 22765000
}
```

## Why this is separate

The core `Ingest` module is domain-agnostic -- it handles PDF text extraction,
OCR quality gating, and generic numeric-sanity checks. KWD/Arabic currency
logic is specific to Kuwaiti financial documents and lives here as an example
of how to extend the pipeline for a particular domain.
