#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

/// Detects "the same purchase logged twice".
///
/// Rule: same amount and currency AND (same non-blank normalized merchant OR same Wallet card name),
/// with the two transaction dates at most 180 seconds apart (inclusive).
public enum DuplicateDetector {
    /// Three minutes, inclusive.
    public static let windowSeconds: TimeInterval = 180

    /// True when `a` and `b` look like the same purchase. A record is never a duplicate of itself (same id).
    public static func isDuplicate(_ a: TransactionRecord, _ b: TransactionRecord) -> Bool {
        guard a.id != b.id else { return false }
        return matches(
            amount: a.amount, currencyCode: a.currencyCode, merchant: a.merchant, paymentMethod: a.paymentMethod, date: a.date,
            existing: b
        )
    }

    /// The first existing record that `candidate` duplicates, if any.
    public static func findDuplicate(of candidate: TransactionRecord, in existing: [TransactionRecord]) -> TransactionRecord? {
        existing.first { isDuplicate(candidate, $0) }
    }

    /// Same check for a transaction that has not been built yet.
    public static func findDuplicate(
        amount: Decimal,
        currencyCode: String = "USD",
        merchant: String,
        paymentMethod: PaymentMethod,
        date: Date,
        in existing: [TransactionRecord]
    ) -> TransactionRecord? {
        existing.first {
            matches(amount: amount, currencyCode: currencyCode, merchant: merchant, paymentMethod: paymentMethod, date: date, existing: $0)
        }
    }

    private static func matches(
        amount: Decimal, currencyCode: String, merchant: String, paymentMethod: PaymentMethod, date: Date,
        existing: TransactionRecord
    ) -> Bool {
        guard amount == existing.amount, currencyCode == existing.currencyCode else { return false }
        guard abs(date.timeIntervalSince(existing.date)) <= windowSeconds else { return false }

        let merchantA = MerchantNormalizer.normalize(merchant)
        let merchantB = MerchantNormalizer.normalize(existing.merchant)
        if !merchantA.isEmpty, merchantA == merchantB { return true }

        if let cardA = paymentMethod.cardName, let cardB = existing.paymentMethod.cardName {
            let a = cardA.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let b = cardB.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !a.isEmpty, a == b { return true }
        }
        return false
    }
}
