import Foundation

/// Currency strings and the one rounding helper. Rounding mode is `.plain`
/// (half away from zero: 0.125 → 0.13, -0.125 → -0.13) everywhere in Ledgerly.
///
/// Formatters are created per call: `NumberFormatter` is not `Sendable`, so nothing is cached.
public enum MoneyFormat {
    /// Rounds with `.plain` (half away from zero) to `scale` fraction digits.
    public static func round(_ value: Decimal, scale: Int = 2) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, .plain)
        return output
    }

    /// Rounds toward zero to `scale` fraction digits (1.999 → 1.99, -1.999 → -1.99).
    public static func truncate(_ value: Decimal, scale: Int = 2) -> Decimal {
        var input = value < 0 ? -value : value
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, .down)
        return value < 0 ? -output : output
    }

    /// "$12.40", "-$5.00", "$1,234.56". Rounded to cents first.
    public static func string(_ amount: Decimal, currencyCode: String = "USD", locale: Locale = .current) -> String {
        format(round(amount, scale: 2), fractionDigits: 2, currencyCode: currencyCode, locale: locale)
    }

    /// Whole dollars for insight copy: "$310", "-$5". Rounded to the nearest dollar first.
    public static func whole(_ amount: Decimal, currencyCode: String = "USD", locale: Locale = .current) -> String {
        format(round(amount, scale: 0), fractionDigits: 0, currencyCode: currencyCode, locale: locale)
    }

    /// Whole dollars when the cents are zero ("$45"), otherwise cents ("$44.37"). Never changes the value beyond cent rounding,
    /// so a list of these always adds up.
    public static func compact(_ amount: Decimal, currencyCode: String = "USD", locale: Locale = .current) -> String {
        let cents = round(amount, scale: 2)
        if cents == round(cents, scale: 0) {
            return format(cents, fractionDigits: 0, currencyCode: currencyCode, locale: locale)
        }
        return format(cents, fractionDigits: 2, currencyCode: currencyCode, locale: locale)
    }

    /// Locale-independent number for CSV and text fields: "12.40", "-5.00", "1234.56" (no grouping, "." decimal,
    /// at least two fraction digits, more only if the value has them).
    public static func plain(_ amount: Decimal) -> String {
        let negative = amount < 0
        let magnitude = negative ? -amount : amount
        var text = NSDecimalNumber(decimal: magnitude).description(withLocale: Locale(identifier: "en_US_POSIX"))
        if text.contains("e") || text.contains("E") || text == "NaN" {
            text = "\(magnitude)"
        }
        if let dot = text.firstIndex(of: ".") {
            let fraction = text[text.index(after: dot)...].count
            if fraction < 2 { text += String(repeating: "0", count: 2 - fraction) }
        } else {
            text += ".00"
        }
        return (negative ? "-" : "") + text
    }

    /// "40%" from 0.4. Rounded to a whole percent.
    public static func percent(_ fraction: Decimal) -> String {
        let value = round(fraction * 100, scale: 0)
        return "\(NSDecimalNumber(decimal: value).stringValue)%"
    }

    /// The currency symbol a locale uses for a code ("$" for USD in en_US).
    public static func currencySymbol(currencyCode: String = "USD", locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.currencySymbol ?? currencyCode
    }

    /// `Double` for plotting only. Never feed the result back into money math.
    public static func double(_ amount: Decimal) -> Double {
        NSDecimalNumber(decimal: amount).doubleValue
    }

    private static func format(_ rounded: Decimal, fractionDigits: Int, currencyCode: String, locale: Locale) -> String {
        let negative = rounded < 0
        let magnitude = negative ? -rounded : rounded
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        let body = formatter.string(from: NSDecimalNumber(decimal: magnitude))
            ?? "\(currencyCode) \(plain(magnitude))"
        // The sign is added by hand so every platform prints "-$5.00" the same way.
        return negative ? "-" + body : body
    }
}
