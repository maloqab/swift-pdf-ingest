// NumericSanity+Financial.swift
// FinancialArabicPlugin — standalone reference code for KWD / Arabic currency detection.
//
// Copy this file (and SourceCurrencyUnit.swift) into your own project.
// It has no dependency on the Ingest module.

import Foundation

// MARK: - Detection

/// Examines a block of text (e.g. a page header or footer) and decides whether
/// the financial values on that page are expressed in raw KWD or in KD '000s.
///
/// The function recognises both Latin hints (e.g. "KD'000", "KWD 000S") and
/// Arabic hints (e.g. "بالألف د.ك", "الأرقام بالألاف دينار كويتي").
public func detectFinancialSourceUnit(in text: String) -> SourceCurrencyUnit {
    let normalizedLatin = normalizeLatinHint(text)
    let compactLatin = normalizedLatin.replacingOccurrences(of: " ", with: "")

    let latinHints = [
        "KD'000", "KD'000S", "KWD'000", "KWD'000S",
        "KD 000", "KD 000S", "KWD 000", "KWD 000S",
        "KD000", "KD000S", "KWD000", "KWD000S",
        "000 KD", "000 KWD"
    ]

    if latinHints.contains(where: {
        normalizedLatin.contains($0)
            || compactLatin.contains($0.replacingOccurrences(of: " ", with: ""))
    }) {
        return .kdThousands
    }

    let normalizedArabic = normalizeArabicHint(text)
    let compactArabic = normalizedArabic.replacingOccurrences(of: " ", with: "")

    let arabicHints = [
        "بالالف", "بالالاف", "الاف", "الف",
        "الفد.ك", "الافد.ك", "الفديناركويتي", "الافديناركويتي",
        "الافدينار", "الفدينار", "د.كالف", "د.كالاف", "دكالف", "دكالاف"
    ]

    if arabicHints.contains(where: { compactArabic.contains($0) }) {
        return .kdThousands
    }

    return .kwd
}

// MARK: - Normalization

/// Scales a parsed numeric value according to its source unit.
///
/// If the value was expressed in KD '000s the function multiplies by 1 000;
/// raw KWD values are returned unchanged.
public func normalizeKWDValue(_ value: Decimal, sourceUnit: SourceCurrencyUnit) -> Decimal {
    switch sourceUnit {
    case .kwd:
        return value
    case .kdThousands:
        return value * Decimal(1000)
    }
}

/// Convenience function that combines parsing, unit detection, and scaling
/// into a single call — handy for chatbot pipelines.
///
/// - Parameters:
///   - rawNumericLiteral: The numeric string extracted from the document
///     (e.g. `"22,765"`).
///   - sourceTextOrUnitHint: A piece of surrounding text (e.g. a table header)
///     that hints at the unit, or a direct unit string like `"KD_000"`.
/// - Returns: The fully-scaled `Decimal` value, or `nil` if parsing fails.
public func normalizedKWDValueForChatbot(
    rawNumericLiteral: String,
    sourceTextOrUnitHint: String
) -> Decimal? {
    guard let value = decimalFromRaw(rawNumericLiteral) else {
        return nil
    }

    let unit: SourceCurrencyUnit
    let normalizedLatin = normalizeLatinHint(sourceTextOrUnitHint)
    if normalizedLatin == SourceCurrencyUnit.kdThousands.rawValue
        || normalizedLatin.contains("KD'000")
        || normalizedLatin.contains("KWD'000")
        || normalizedLatin.contains("KD 000")
    {
        unit = .kdThousands
    } else {
        unit = detectFinancialSourceUnit(in: sourceTextOrUnitHint)
    }

    return normalizeKWDValue(value, sourceUnit: unit)
}

// MARK: - Private helpers

/// Parses a raw numeric string into a Decimal, stripping commas and spaces.
private func decimalFromRaw(_ raw: String) -> Decimal? {
    let cleaned = raw
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: ",", with: "")
        .replacingOccurrences(of: "\u{066C}", with: "")  // Arabic thousands separator
    return Decimal(string: cleaned)
}

/// Normalizes Latin-script quote variants so that hints like KD\u{2018}000
/// are matched uniformly.
private func normalizeLatinHint(_ text: String) -> String {
    text
        .uppercased()
        .replacingOccurrences(of: "\u{2019}", with: "'")   // right single quote
        .replacingOccurrences(of: "`", with: "'")
        .replacingOccurrences(of: "\u{00B4}", with: "'")   // acute accent
        .replacingOccurrences(of: "\u{2018}", with: "'")   // left single quote
}

/// Normalizes Arabic text for fuzzy hint matching (collapses hamza forms,
/// removes tatweel, etc.).
private func normalizeArabicHint(_ text: String) -> String {
    text
        .lowercased()
        .replacingOccurrences(of: "\u{0623}", with: "\u{0627}")  // أ → ا
        .replacingOccurrences(of: "\u{0625}", with: "\u{0627}")  // إ → ا
        .replacingOccurrences(of: "\u{0622}", with: "\u{0627}")  // آ → ا
        .replacingOccurrences(of: "\u{0649}", with: "\u{064A}")  // ى → ي
        .replacingOccurrences(of: "\u{0629}", with: "\u{0647}")  // ة → ه
        .replacingOccurrences(of: "\u{0640}", with: "")          // tatweel
        .replacingOccurrences(of: "\u{2019}", with: "'")
        .replacingOccurrences(of: "`", with: "'")
}
