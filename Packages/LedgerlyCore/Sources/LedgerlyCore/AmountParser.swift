import Foundation

/// Turns the text Shortcuts (or a CSV cell) hands us into a `Decimal`.
///
/// The rules, in order:
/// 1. Whitespace is trimmed. Blank input → `nil`. Input with no digit at all ("abc") → `nil`.
/// 2. Digits in other scripts (Arabic-Indic, Eastern Arabic-Indic, full-width) become ASCII digits,
///    and the Arabic decimal/thousands marks (U+066B / U+066C) become "." / ",".
/// 3. Everything before the first digit and after the last digit is decoration: currency symbols,
///    currency codes, signs, brackets. Decoration may not contain digits (by construction), and the
///    text between the first and last digit may only contain digits, ".", ",", and group marks
///    (space, no-break space, narrow no-break space, thin space, apostrophe, underscore). Anything else,
///    e.g. "12 and 13" or "1e5", → `nil`.
/// 4. Negative when the decoration has a minus sign ("-5.00", "-$5", "$-5", "5.00-", U+2212)
///    or wraps the number in brackets "(5.00)".
/// 5. Decimal separator:
///    - "." and "," both present → whichever comes LAST is the decimal separator; the other one is
///      grouping. The decimal separator may then appear only once ("1.234.56,7,8" → `nil`).
///    - only one of them, used more than once → grouping ("1,234,567", "1.234.567").
///    - only one of them, used once:
///        · not exactly three digits after it → decimal ("12,40", "12.4", "0,5").
///        · exactly three digits after it → ambiguous ("1,234" / "1.234"). It is the decimal
///          separator when the integer part could not be a group (empty, "0", or more than three
///          digits), when space/apostrophe grouping is already present ("1 234,567"), or when it is
///          the locale's decimal separator. Otherwise it is grouping.
///      So "1,234" is 1234 in en_US and 1.234 in de_DE; "1.234" is 1.234 in en_US and 1234 in de_DE.
///    - a leading separator counts as "0." (".50" → 0.50) unless a letter comes right before it ("Rs.500" → 500).
/// 6. Space/apostrophe groups must be well formed (1–3 digits, then groups of exactly 3), otherwise `nil`.
/// 7. More than 38 digits → `nil` (outside what `Decimal` can hold exactly).
public enum AmountParser {
    /// Parses an amount. Returns `nil` when the text holds no usable number; `"0"` parses to 0.
    public static func parse(_ text: String, locale: Locale = .current) -> Decimal? {
        let scalars = normalizedScalars(text)
        guard let firstDigit = scalars.firstIndex(where: isDigit),
              let lastDigit = scalars.lastIndex(where: isDigit) else { return nil }

        var start = firstDigit
        // ".50" / ",50": pull a leading separator into the number unless a letter sits right before it.
        if start > 0, scalars[start - 1] == "." || scalars[start - 1] == "," {
            let before: Unicode.Scalar? = start > 1 ? scalars[start - 2] : nil
            if before.map({ !$0.properties.isAlphabetic && !isDigit($0) }) ?? true {
                start -= 1
            }
        }
        let prefix = scalars[..<start]
        let suffix = scalars[(lastDigit + 1)...]
        let core = Array(scalars[start...lastDigit])

        let minusSigns: Set<Unicode.Scalar> = ["-", "\u{2212}", "\u{FE63}", "\u{FF0D}"]
        var negative = prefix.contains(where: minusSigns.contains) || suffix.contains(where: minusSigns.contains)
        if prefix.contains("("), suffix.contains(")") { negative = true }

        // Split the core into digits, separators and group marks.
        var hadGroupMarks = false
        var compact: [Unicode.Scalar] = []      // digits plus "." and ","
        var groupRuns: [Int] = []               // digit-run lengths between group marks, before any separator
        var currentRun = 0
        var seenSeparator = false
        for scalar in core {
            if isDigit(scalar) {
                compact.append(scalar)
                if !seenSeparator { currentRun += 1 }
            } else if scalar == "." || scalar == "," {
                compact.append(scalar)
                seenSeparator = true
            } else if isGroupMark(scalar) {
                if seenSeparator { return nil }             // "1,5 00"
                hadGroupMarks = true
                groupRuns.append(currentRun)
                currentRun = 0
            } else {
                return nil
            }
        }
        if hadGroupMarks {
            groupRuns.append(currentRun)
            guard let first = groupRuns.first, (1...3).contains(first),
                  groupRuns.dropFirst().allSatisfy({ $0 == 3 }) else { return nil }
        }

        let dotCount = compact.filter { $0 == "." }.count
        let commaCount = compact.filter { $0 == "," }.count
        var decimalSeparator: Unicode.Scalar?

        if dotCount > 0 && commaCount > 0 {
            let lastDot = compact.lastIndex(of: ".") ?? 0
            let lastComma = compact.lastIndex(of: ",") ?? 0
            let decimal: Unicode.Scalar = lastDot > lastComma ? "." : ","
            if (decimal == "." ? dotCount : commaCount) != 1 { return nil }
            decimalSeparator = decimal
        } else if dotCount + commaCount == 1 {
            let separator: Unicode.Scalar = dotCount == 1 ? "." : ","
            let index = compact.firstIndex(of: separator) ?? 0
            let integerDigits = Array(compact[..<index])
            let fractionCount = compact.count - index - 1
            if fractionCount != 3 {
                decimalSeparator = separator
            } else if hadGroupMarks || integerDigits.isEmpty || integerDigits.count > 3 || integerDigits.first == "0" {
                decimalSeparator = separator
            } else if String(Character(separator)) == localeDecimalSeparator(locale) {
                decimalSeparator = separator
            } else {
                decimalSeparator = nil      // grouping
            }
        } else {
            decimalSeparator = nil          // none, or one kind repeated → grouping
        }

        var integerPart = ""
        var fractionPart = ""
        var inFraction = false
        for scalar in compact {
            if isDigit(scalar) {
                if inFraction { fractionPart.unicodeScalars.append(scalar) } else { integerPart.unicodeScalars.append(scalar) }
            } else if scalar == decimalSeparator {
                inFraction = true
            }
        }
        if integerPart.isEmpty { integerPart = "0" }
        guard integerPart.count + fractionPart.count <= 38 else { return nil }

        let canonical = fractionPart.isEmpty ? integerPart : integerPart + "." + fractionPart
        guard let magnitude = Decimal(string: canonical, locale: Locale(identifier: "en_US_POSIX")), !magnitude.isNaN else { return nil }
        if magnitude == 0 { return 0 }
        return negative ? -magnitude : magnitude
    }

    // MARK: Helpers

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x30 && scalar.value <= 0x39
    }

    private static func isGroupMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x20, 0xA0, 0x202F, 0x2009, 0x2007, 0x27, 0x2019, 0x5F: return true
        default: return false
        }
    }

    private static func localeDecimalSeparator(_ locale: Locale) -> String {
        if let separator = locale.decimalSeparator, !separator.isEmpty { return separator }
        return "."
    }

    /// Trims, maps non-ASCII digits to ASCII, maps Arabic separators, and drops invisible direction marks.
    private static func normalizedScalars(_ text: String) -> [Unicode.Scalar] {
        var result: [Unicode.Scalar] = []
        for scalar in text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars {
            let value = scalar.value
            var mapped: UInt32?
            switch value {
            case 0x0660...0x0669: mapped = value - 0x0660 + 0x30     // Arabic-Indic
            case 0x06F0...0x06F9: mapped = value - 0x06F0 + 0x30     // Eastern Arabic-Indic
            case 0xFF10...0xFF19: mapped = value - 0xFF10 + 0x30     // full-width
            case 0x066B: mapped = 0x2E                               // Arabic decimal separator
            case 0x066C: mapped = 0x2C                               // Arabic thousands separator
            case 0xFF0E: mapped = 0x2E                               // full-width full stop
            case 0xFF0C: mapped = 0x2C                               // full-width comma
            case 0x200E, 0x200F, 0x061C, 0x202A...0x202E, 0xFEFF: continue   // direction marks, BOM
            default: mapped = nil
            }
            if let mapped, let ascii = Unicode.Scalar(mapped) {
                result.append(ascii)
            } else {
                result.append(scalar)
            }
        }
        return result
    }
}
