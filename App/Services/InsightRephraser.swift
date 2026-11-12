// InsightRephraser.swift — optional on-device rewording of insight text; every number still comes from the engine.

import Foundation
import LedgerlyCore
#if canImport(FoundationModels)
import FoundationModels
#endif

enum InsightRephraser {
    /// Returns the same insights, with the body text reworded by Apple's on-device model when
    /// that model exists and is ready. Otherwise (older iOS, older SDK, model unavailable, any
    /// error) it returns the input untouched, without telling anyone.
    ///
    /// Only `body` can change. A rewrite is thrown away unless it contains exactly the same
    /// numbers as the original, so the model can never invent or alter a figure.
    static func rephrase(_ insights: [Insight]) async -> [Insight] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if LaunchFlags.isUITesting { return insights }
            return await rephraseWithModel(insights)
        }
        #endif
        return insights
    }

    // MARK: - The numbers rule (plain Swift, always compiled)

    /// True when `rewritten` is an acceptable replacement for `original`: not empty, not wildly
    /// longer, and carrying exactly the same numbers (digits and spelled-out) the same number of times.
    static func isSafeRewrite(original: String, rewritten: String) -> Bool {
        let text = rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return false }
        if text.count > original.count * 2 + 40 { return false }
        if numberTokens(in: original) != numberTokens(in: text) { return false }
        if numberWords(in: original) != numberWords(in: text) { return false }
        return true
    }

    /// Every number in the text, sorted: "$1,234.50, 40% above $220." gives ["1234.50", "220", "40"].
    /// A comma or full stop only counts as part of a number when it has a digit on both sides.
    static func numberTokens(in text: String) -> [String] {
        let characters = Array(text)
        var tokens: [String] = []
        var current = ""
        for index in characters.indices {
            let character = characters[index]
            if character.isASCII && character.isNumber {
                current.append(character)
                continue
            }
            let isSeparator = character == "," || character == "."
            let previousIsDigit = !current.isEmpty
            var nextIsDigit = false
            if index + 1 < characters.count {
                let next = characters[index + 1]
                nextIsDigit = next.isASCII && next.isNumber
            }
            if isSeparator && previousIsDigit && nextIsDigit {
                if character == "." { current.append(character) }
                continue
            }
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens.sorted()
    }

    /// Spelled-out numbers and multipliers in the text, sorted, so "one" can't quietly become "two"
    /// and "halving" can't become "doubling".
    static func numberWords(in text: String) -> [String] {
        let watched: Set<String> = [
            "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
            "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
            "nineteen", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
            "hundred", "thousand", "million", "half", "halve", "halving", "double", "doubling",
            "twice", "triple", "quarter", "third", "dozen"
        ]
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter })
        var found: [String] = []
        for word in words {
            let value = String(word)
            if watched.contains(value) { found.append(value) }
        }
        return found.sorted()
    }

    // MARK: - Foundation Models (iOS 26 SDK only)

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func rephraseWithModel(_ insights: [Insight]) async -> [Insight] {
        guard case .available = SystemLanguageModel.default.availability else { return insights }

        let instructions = "You reword one short personal-finance tip so it sounds friendly and natural. Keep every number, dollar amount, percentage, merchant name and category name exactly as written. Do not add numbers, advice or facts. Reply with the reworded tip only, in one or two sentences."
        var output = insights
        for index in insights.indices {
            let original = insights[index].body
            do {
                // A fresh session per card keeps each request small and independent.
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: original)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if isSafeRewrite(original: original, rewritten: text) {
                    output[index].body = text
                }
            } catch {
                // Any failure (model busy, guardrail, context limit): keep what we have so far.
                return output
            }
        }
        return output
    }
    #endif
}
