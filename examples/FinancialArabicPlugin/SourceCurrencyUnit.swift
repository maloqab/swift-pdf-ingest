// SourceCurrencyUnit.swift
// FinancialArabicPlugin — standalone reference code for KWD / Arabic currency detection.
//
// Copy this file into your own project. It has no dependency on the Ingest module.

import Foundation

/// Identifies the unit scale of a Kuwaiti-Dinar-denominated financial value.
///
/// Many Kuwaiti financial statements express amounts in "KD '000s" (thousands
/// of Kuwaiti Dinars). This enum lets you distinguish between raw KWD values
/// and values that need to be multiplied by 1 000 to recover the full amount.
public enum SourceCurrencyUnit: String, Sendable {
    /// Raw Kuwaiti Dinar value — no scaling needed.
    case kwd = "KWD"

    /// Value expressed in thousands of Kuwaiti Dinars (multiply by 1 000).
    case kdThousands = "KD_000"
}
