import Foundation

public enum SourceCurrencyUnit: String, Sendable {
    case kwd = "KWD"
    case kdThousands = "KD_000"
}

public enum NumericReasonCode: String, CaseIterable, Sendable {
    case malformedDecimal = "malformed_decimal"
    case impossibleNegativeTotal = "impossible_negative_total"
    case delimiterCorruption = "delimiter_corruption"
    case digitGlyphConfusion = "digit_glyph_confusion"
}

public struct NumericSanityReport: Sendable {
    public let reasonCodes: [NumericReasonCode]

    public init(reasonCodes: [NumericReasonCode]) {
        self.reasonCodes = reasonCodes
    }

    public var isSuspicious: Bool { !reasonCodes.isEmpty }
}

public enum NumericSanity {
    public static func analyze(text: String) -> NumericSanityReport {
        guard !text.isEmpty else { return NumericSanityReport(reasonCodes: []) }

        var codes = Set<NumericReasonCode>()

        if hasMalformedDecimal(in: text) {
            codes.insert(.malformedDecimal)
        }

        if hasImpossibleNegativeTotal(in: text) {
            codes.insert(.impossibleNegativeTotal)
        }

        if hasDelimiterCorruption(in: text) {
            codes.insert(.delimiterCorruption)
        }

        if hasDigitGlyphConfusion(in: text) {
            codes.insert(.digitGlyphConfusion)
        }

        return NumericSanityReport(reasonCodes: Array(codes).sorted { $0.rawValue < $1.rawValue })
    }

    public static func repairDigitGlyphConfusions(in text: String) -> String {
        guard !text.isEmpty else { return text }
        guard let regex = try? NSRegularExpression(pattern: #"\(?[A-Za-z0-9٠-٩]{1,4}[\.,][A-Za-z0-9٠-٩]{1,4}\)?"#) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return text }

        var repaired = text
        for match in matches.reversed() {
            guard let tokenRange = Range(match.range, in: repaired) else { continue }
            let token = String(repaired[tokenRange])
            let replacement = repairNumericToken(token)
            repaired.replaceSubrange(tokenRange, with: replacement)
        }

        return repaired
    }

    public static func detectSourceUnit(in text: String) -> SourceCurrencyUnit {
        let normalizedLatin = normalizeLatinHint(text)
        let compactLatin = normalizedLatin.replacingOccurrences(of: " ", with: "")

        let latinHints = [
            "KD'000", "KD'000S", "KWD'000", "KWD'000S",
            "KD 000", "KD 000S", "KWD 000", "KWD 000S",
            "KD000", "KD000S", "KWD000", "KWD000S",
            "000 KD", "000 KWD"
        ]

        if latinHints.contains(where: { normalizedLatin.contains($0) || compactLatin.contains($0.replacingOccurrences(of: " ", with: "")) }) {
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

    public static func normalizeKWDValue(_ value: Decimal, sourceUnit: SourceCurrencyUnit) -> Decimal {
        switch sourceUnit {
        case .kwd:
            return value
        case .kdThousands:
            return value * Decimal(1000)
        }
    }

    public static func normalizedKWDValueForChatbot(
        rawNumericLiteral: String,
        sourceTextOrUnitHint: String
    ) -> Decimal? {
        guard let value = decimal(from: rawNumericLiteral) else {
            return nil
        }

        let unit: SourceCurrencyUnit
        let normalizedLatin = normalizeLatinHint(sourceTextOrUnitHint)
        if normalizedLatin == SourceCurrencyUnit.kdThousands.rawValue || normalizedLatin.contains("KD'000") || normalizedLatin.contains("KWD'000") || normalizedLatin.contains("KD 000") {
            unit = .kdThousands
        } else {
            unit = detectSourceUnit(in: sourceTextOrUnitHint)
        }

        return normalizeKWDValue(value, sourceUnit: unit)
    }

    public static func decimal(from raw: String) -> Decimal? {
        let cleaned = raw
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "٬", with: "")
        return Decimal(string: cleaned)
    }


    public static func groupedNumberFidelityScore(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        guard let wellFormed = try? NSRegularExpression(pattern: #"\(?\b\d{1,3}(?:,\d{3})+\b\)?"#),
              let malformed = try? NSRegularExpression(pattern: #"\b\d{1,3},\d{1,2}\b"#) else {
            return 0
        }

        let range = NSRange(text.startIndex..., in: text)
        let goodCount = wellFormed.numberOfMatches(in: text, range: range)
        let badCount = malformed.numberOfMatches(in: text, range: range)
        return max(0, goodCount - badCount)
    }


    private static func normalizeLatinHint(_ text: String) -> String {
        text
            .uppercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "`", with: "'")
            .replacingOccurrences(of: "´", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
    }

    private static func normalizeArabicHint(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "أ", with: "ا")
            .replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "آ", with: "ا")
            .replacingOccurrences(of: "ى", with: "ي")
            .replacingOccurrences(of: "ة", with: "ه")
            .replacingOccurrences(of: "\u{0640}", with: "")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "`", with: "'")
    }

    private static func hasMalformedDecimal(in text: String) -> Bool {
        let patterns = [
            #"\b\d+[\.,]\d+[\.,]\d+\b"#,
            #"\b\d{1,3}(?:,\d{3})*\.\d+\.\d+\b"#
        ]
        return patterns.contains { pattern in
            regex(pattern, in: text)
        }
    }

    private static func hasImpossibleNegativeTotal(in text: String) -> Bool {
        let pattern = #"(?i)(total\s+(assets|revenue|equity|liabilities)|net\s+(profit|income))\s*[:\-]?\s*-\s*\d"#
        return regex(pattern, in: text)
    }

    private static func hasDelimiterCorruption(in text: String) -> Bool {
        let patterns = [
            #"\d[\.,]{2,}\d"#,
            #"\b\d{1,3}(?:[\.,]\d{1,2}){3,}\b"#,
            #"\b\d{3,},\d{1,2}\b"#
        ]
        return patterns.contains { pattern in
            regex(pattern, in: text)
        }
    }

    private static func hasDigitGlyphConfusion(in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"\(?[A-Za-z0-9٠-٩]{1,4}[\.,][A-Za-z0-9٠-٩]{1,4}\)?"#) else {
            return false
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let token = String(text[range])
            let scalars = token.unicodeScalars
            let hasLatinLetter = scalars.contains { CharacterSet.letters.contains($0) && !(0x0600...0x06FF).contains(Int($0.value)) }
            let hasAsciiDigit = scalars.contains { CharacterSet.decimalDigits.contains($0) && (0x0030...0x0039).contains(Int($0.value)) }
            let hasArabicDigit = scalars.contains { (0x0660...0x0669).contains(Int($0.value)) }
            if (hasLatinLetter && (hasAsciiDigit || hasArabicDigit)) || (hasAsciiDigit && hasArabicDigit) {
                return true
            }
        }

        return false
    }

    private static func repairNumericToken(_ token: String) -> String {
        let hasLeadingParen = token.hasPrefix("(")
        let hasTrailingParen = token.hasSuffix(")")
        let core = token.trimmingCharacters(in: CharacterSet(charactersIn: "()"))

        guard let delimiter = core.first(where: { $0 == "," || $0 == "." }) else {
            return token
        }

        let parts = core.split(separator: delimiter, maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return token
        }

        let mappedLeft = mapGlyphsToDigits(parts[0])
        let mappedRight = mapGlyphsToDigits(parts[1])

        guard !mappedLeft.isEmpty, !mappedRight.isEmpty else {
            return token
        }

        let normalizedRight = String(mappedRight.prefix(3))
        let normalizedCore = "\(mappedLeft),\(normalizedRight)"
        return "\(hasLeadingParen ? "(" : "")\(normalizedCore)\(hasTrailingParen ? ")" : "")"
    }

    private static func mapGlyphsToDigits(_ text: String) -> String {
        let glyphMap: [Character: Character] = [
            "O": "0", "o": "0", "D": "0", "Q": "0",
            "I": "1", "l": "1", "L": "1", "|": "1", "!": "1",
            "Z": "2", "z": "2",
            "E": "3", "e": "3", "c": "3", "C": "3",
            "A": "4", "a": "4",
            "S": "5", "s": "5", "$": "5",
            "G": "6", "g": "6", "d": "6",
            "T": "7",
            "B": "8",
            "q": "9"
        ]

        var out = ""
        for ch in text {
            if ch.isNumber {
                if let scalar = ch.unicodeScalars.first, (0x0660...0x0669).contains(Int(scalar.value)) {
                    let latinDigit = Int(scalar.value - 0x0660)
                    out.append(String(latinDigit))
                } else {
                    out.append(ch)
                }
            } else if let mapped = glyphMap[ch] {
                out.append(mapped)
            }
        }
        return out
    }

    private static func regex(_ pattern: String, in text: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
