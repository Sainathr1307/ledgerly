#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

/// Cleans merchant names so "SHELL OIL 57444", "Shell Oil #57444" and "shell oil" all match.
public enum MerchantNormalizer {
    /// Card-processor prefixes that are dropped when they are followed by "*", e.g. "SQ *BLUE BOTTLE".
    private static let processorPrefixes: Set<String> = ["SQ", "TST", "PP", "PAYPAL", "SP", "DD", "CKE", "FSP", "BT", "IC", "POS"]
    /// Words that only exist to introduce a store number ("STORE 123", "NO 12").
    private static let storeWords: Set<String> = ["STORE", "STR", "NO", "NUM", "NBR", "UNIT", "LOC"]

    /// Normalizes a merchant name for matching:
    /// uppercase → strip diacritics → drop apostrophes → other punctuation becomes a space →
    /// drop processor prefixes ("SQ *") → drop store numbers and reference codes → collapse spaces.
    ///
    /// Number rules: a digits-only token is dropped when it has 3+ digits, follows "#", or follows a
    /// store word; a first token of up to 4 digits is kept ("7 ELEVEN", "1800 FLOWERS"); short numbers
    /// elsewhere are kept ("PHILLIPS 66", "MOTEL 6"). A mixed letter/digit token with 3+ digits is a
    /// reference code and is dropped unless it is the first token; "STARBUCKS1234" loses its digits.
    /// If nothing would be left (the name was only numbers), the cleaned text is returned without number stripping.
    public static func normalize(_ raw: String) -> String {
        let upper = stripDiacritics(raw).uppercased()

        // Pass 1: punctuation handling, remembering which tokens followed "#" and whether a "*" came after the first token.
        var tokens: [(text: String, hashed: Bool)] = []
        var current = ""
        var pendingHash = false
        var currentHashed = false
        var starAfterTokenCount: Int?
        func flush() {
            if !current.isEmpty {
                tokens.append((current, currentHashed))
                current = ""
            }
            currentHashed = false
        }
        for scalar in upper.unicodeScalars {
            if scalar.properties.isAlphabetic || (scalar.value >= 0x30 && scalar.value <= 0x39) {
                if current.isEmpty { currentHashed = pendingHash; pendingHash = false }
                current.unicodeScalars.append(scalar)
            } else if scalar == "'" || scalar == "\u{2019}" || scalar == "\u{2018}" || scalar == "`" {
                continue                                    // McDonald's → MCDONALDS
            } else {
                flush()
                if scalar == "#" { pendingHash = true } else if scalar != " " { pendingHash = false }
                if scalar == "*", starAfterTokenCount == nil { starAfterTokenCount = tokens.count }
            }
        }
        flush()

        // Processor prefix: "SQ *MERCHANT" → "MERCHANT".
        if let starIndex = starAfterTokenCount, starIndex == 1, tokens.count > 1, processorPrefixes.contains(tokens[0].text) {
            tokens.removeFirst()
        }

        let cleaned = tokens.map { $0.text }

        // Pass 2: store numbers and reference codes.
        var kept: [String] = []
        for (index, token) in tokens.enumerated() {
            let digits = token.text.unicodeScalars.filter { $0.value >= 0x30 && $0.value <= 0x39 }.count
            let length = token.text.unicodeScalars.count
            if digits == 0 {
                kept.append(token.text)
                continue
            }
            if digits == length {
                // digits only
                let afterStoreWord = kept.last.map { storeWords.contains($0) } ?? false
                if index == 0 && kept.isEmpty {
                    if length <= 4 && !token.hashed { kept.append(token.text) }
                } else if token.hashed || length >= 3 || afterStoreWord {
                    if afterStoreWord { kept.removeLast() }
                } else {
                    kept.append(token.text)
                }
                continue
            }
            // letters and digits mixed
            if token.hashed { continue }
            if let stripped = strippingTrailingStoreNumber(token.text) {
                kept.append(stripped)
            } else if digits >= 3 && !(index == 0 && kept.isEmpty) {
                continue
            } else {
                kept.append(token.text)
            }
        }
        // A store word left dangling at the end ("TARGET STORE") is noise only if a number followed it; that case was handled above.

        let result = kept.joined(separator: " ")
        if result.isEmpty { return cleaned.joined(separator: " ") }
        return result
    }

    /// Splits a normalized name into its words.
    public static func tokens(_ normalized: String) -> [String] {
        normalized.split(separator: " ").map(String.init)
    }

    /// Trims and collapses whitespace but otherwise keeps the name as the user/Wallet wrote it. Used for display.
    public static func displayName(_ raw: String) -> String {
        raw.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\u{00A0}" }).joined(separator: " ")
    }

    /// True when the name is empty or only whitespace.
    public static func isBlank(_ raw: String?) -> Bool {
        guard let raw else { return true }
        return displayName(raw).isEmpty
    }

    /// Lowercases and strips diacritics — the folding used by search so "cafe" finds "Café".
    public static func searchKey(_ text: String) -> String {
        stripDiacritics(text).lowercased()
    }

    // MARK: Helpers

    /// "STARBUCKS1234" → "STARBUCKS": three or more letters followed by three or more digits.
    private static func strippingTrailingStoreNumber(_ token: String) -> String? {
        let scalars = Array(token.unicodeScalars)
        guard let firstDigit = scalars.firstIndex(where: { $0.value >= 0x30 && $0.value <= 0x39 }) else { return nil }
        let head = scalars[..<firstDigit]
        let tail = scalars[firstDigit...]
        guard head.count >= 3, tail.count >= 3,
              tail.allSatisfy({ $0.value >= 0x30 && $0.value <= 0x39 }) else { return nil }
        var text = ""
        text.unicodeScalars.append(contentsOf: head)
        return text
    }

    private static func stripDiacritics(_ text: String) -> String {
        var result = ""
        for scalar in text.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark:
                continue
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
