import Foundation

/// A transaction as it arrives from outside: the Wallet shortcut, FinanceKit or a CSV row.
public struct IncomingTransaction: Hashable, Codable, Sendable {
    /// The amount exactly as received ("$12.40", "12,40", "", …).
    public var rawAmount: String
    public var merchant: String?
    /// Wallet card name, if any.
    public var cardName: String?
    public var date: Date
    public var source: SourceKind
    /// Nil → the ingestor's default currency.
    public var currencyCode: String?
    public var notes: String
    /// A category name that came with the data (CSV "Category" column). Used after learned rules, before keywords.
    public var categoryHint: String?
    /// Flip the sign after parsing. For bank exports where purchases are negative.
    public var negateAmount: Bool

    public init(
        rawAmount: String,
        merchant: String? = nil,
        cardName: String? = nil,
        date: Date,
        source: SourceKind = .walletShortcut,
        currencyCode: String? = nil,
        notes: String = "",
        categoryHint: String? = nil,
        negateAmount: Bool = false
    ) {
        self.rawAmount = rawAmount
        self.merchant = merchant
        self.cardName = cardName
        self.date = date
        self.source = source
        self.currencyCode = currencyCode
        self.notes = notes
        self.categoryHint = categoryHint
        self.negateAmount = negateAmount
    }
}

/// Why an ingested transaction was sent to Needs Review.
public enum ReviewReason: String, Codable, CaseIterable, Sendable {
    /// The amount parsed to exactly 0.
    case zeroAmount
    /// The amount was blank or not a number; it is stored as 0.
    case unparseableAmount
    /// No merchant name; it is stored as "".
    case blankMerchant
    /// Matches an existing transaction within three minutes.
    case possibleDuplicate
}

public struct IngestResult: Hashable, Sendable {
    /// The record to save. Always present — bad input is saved with `needsReview = true`, never dropped.
    public var record: TransactionRecord
    public var categorization: CategorizationResult
    /// Empty when the transaction is clean.
    public var reviewReasons: [ReviewReason]
    /// The id of the existing transaction this one seems to duplicate.
    public var duplicateOfID: UUID?

    public init(record: TransactionRecord, categorization: CategorizationResult, reviewReasons: [ReviewReason] = [], duplicateOfID: UUID? = nil) {
        self.record = record
        self.categorization = categorization
        self.reviewReasons = reviewReasons
        self.duplicateOfID = duplicateOfID
    }
}

/// Pure pipeline: `IncomingTransaction` → parsed, categorized, duplicate-checked `TransactionRecord`.
/// Used by the "Log Wallet Transaction" intent, FinanceKit and CSV import.
public struct TransactionIngestor: Sendable {
    public let categorizer: Categorizer
    public let defaultCurrencyCode: String
    private let localeIdentifier: String

    /// - Parameter locale: used by `AmountParser` for ambiguous amounts such as "1,234".
    public init(categorizer: Categorizer, locale: Locale = .current, defaultCurrencyCode: String = "USD") {
        self.categorizer = categorizer
        self.localeIdentifier = locale.identifier
        self.defaultCurrencyCode = defaultCurrencyCode
    }

    public var locale: Locale { Locale(identifier: localeIdentifier) }

    /// Builds the record to save.
    ///
    /// - Amount 0, or blank/unparseable (stored as 0) → `needsReview`.
    /// - Blank merchant (stored as "") → `needsReview`, category Other.
    /// - Same amount and (merchant or Wallet card) within 180 s of something in `existing`
    ///   → `isPossibleDuplicate` and `needsReview`. Skipped when `checkDuplicates` is false or the amount is 0.
    /// - Parameters:
    ///   - existing: transactions already saved (only those near `incoming.date` matter).
    ///   - now: becomes `createdAt`.
    ///   - id: the new record's id (injectable for tests).
    public func ingest(
        _ incoming: IncomingTransaction,
        existing: [TransactionRecord] = [],
        now: Date,
        id: UUID = UUID(),
        checkDuplicates: Bool = true
    ) -> IngestResult {
        var reasons: [ReviewReason] = []

        var amount: Decimal = 0
        if let parsed = AmountParser.parse(incoming.rawAmount, locale: locale) {
            amount = incoming.negateAmount ? -parsed : parsed
            if parsed == 0 {
                amount = 0
                reasons.append(.zeroAmount)
            }
        } else {
            reasons.append(.unparseableAmount)
        }

        let merchant = MerchantNormalizer.displayName(incoming.merchant ?? "")
        if merchant.isEmpty { reasons.append(.blankMerchant) }

        let card = MerchantNormalizer.displayName(incoming.cardName ?? "")
        let paymentMethod: PaymentMethod
        if card.isEmpty {
            paymentMethod = .otherCard
        } else if card.lowercased() == "cash" {
            paymentMethod = .cash
        } else if card.lowercased() == "other card" {
            paymentMethod = .otherCard
        } else {
            paymentMethod = .walletCard(card)
        }

        let categorization = categorizer.categorize(merchant: merchant, categoryHint: incoming.categoryHint)
        let currency = (incoming.currencyCode?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0.uppercased() }
            ?? defaultCurrencyCode

        var duplicateOfID: UUID?
        if checkDuplicates, amount != 0,
           let match = DuplicateDetector.findDuplicate(
               amount: amount, currencyCode: currency, merchant: merchant, paymentMethod: paymentMethod, date: incoming.date, in: existing
           ) {
            duplicateOfID = match.id
            reasons.append(.possibleDuplicate)
        }

        let record = TransactionRecord(
            id: id,
            amount: amount,
            currencyCode: currency,
            merchant: merchant,
            categoryID: categorization.categoryID,
            date: incoming.date,
            paymentMethod: paymentMethod,
            source: incoming.source,
            notes: incoming.notes,
            needsReview: !reasons.isEmpty,
            isPossibleDuplicate: duplicateOfID != nil,
            createdAt: now
        )
        return IngestResult(record: record, categorization: categorization, reviewReasons: reasons, duplicateOfID: duplicateOfID)
    }

    // MARK: Notification text

    /// Title for the local notification posted after logging.
    public static func notificationTitle(for record: TransactionRecord) -> String {
        if record.isPossibleDuplicate { return "Possible duplicate" }
        if record.needsReview { return "Needs review" }
        return record.amount < 0 ? "Refund logged" : "Transaction logged"
    }

    /// Body for the local notification:
    /// - clean: "Logged $12.40 at Starbucks · Food & Dining" (refund: "Logged $5.00 refund from Target · Shopping")
    /// - duplicate: "Possible duplicate: $12.40 at Starbucks. Tap to review."
    /// - missing amount: "Saved a purchase at Starbucks, but the amount is missing. Tap to review."
    /// - missing merchant: "Logged $12.40, but the merchant is missing. Tap to review."
    /// - both missing: "Saved a Wallet transaction with missing details. Tap to review."
    public static func notificationText(for record: TransactionRecord, categoryName: String?, locale: Locale = .current) -> String {
        let merchant = MerchantNormalizer.displayName(record.merchant)
        let magnitude = record.amount < 0 ? -record.amount : record.amount
        let money = MoneyFormat.string(magnitude, currencyCode: record.currencyCode, locale: locale)
        let hasAmount = record.amount != 0
        let hasMerchant = !merchant.isEmpty
        let isRefund = record.amount < 0

        if record.isPossibleDuplicate {
            if hasMerchant { return "Possible duplicate: \(money) \(isRefund ? "refund from" : "at") \(merchant). Tap to review." }
            return "Possible duplicate: \(money)\(isRefund ? " refund" : ""). Tap to review."
        }
        if !hasAmount && !hasMerchant {
            return "Saved a \(sourceWord(record.source)) transaction with missing details. Tap to review."
        }
        if !hasAmount {
            return "Saved a purchase at \(merchant), but the amount is missing. Tap to review."
        }
        if !hasMerchant {
            return "Logged \(money)\(isRefund ? " refund" : ""), but the merchant is missing. Tap to review."
        }
        var text = isRefund ? "Logged \(money) refund from \(merchant)" : "Logged \(money) at \(merchant)"
        if let category = categoryName?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty {
            text += " · \(category)"
        }
        if record.needsReview { text += ". Tap to review." }
        return text
    }

    private static func sourceWord(_ source: SourceKind) -> String {
        switch source {
        case .walletShortcut: return "Wallet"
        case .financeKit: return "FinanceKit"
        case .manual: return "manual"
        case .csvImport: return "imported"
        }
    }
}

/// A place transactions can be pulled from (FinanceKit conforms in the app, behind a flag).
public protocol TransactionSource: Sendable {
    var kind: SourceKind { get }
    /// False when the source cannot work on this device/build (missing entitlement, unsupported region, …).
    func isAvailable() async -> Bool
    /// New transactions since `since` (nil = everything the source has).
    func fetch(since: Date?) async throws -> [IncomingTransaction]
}

/// When to show the monthly "How much do you want to save this month?" sheet.
public enum GoalPrompt {
    /// $200 — the goal used the very first time.
    public static var defaultGoal: Decimal { 200 }

    /// "yyyy-MM" for the month containing `now` — store this in `AppSettings.lastGoalPromptMonth` after showing the sheet.
    public static func monthString(now: Date, calendar: LedgerCalendar) -> String {
        MonthKey(date: now, calendar: calendar).stringValue
    }

    /// True on first launch (nil/blank/garbled `lastPromptMonth`) and on the first open of any month
    /// other than the one last prompted for.
    public static func shouldPrompt(lastPromptMonth: String?, now: Date, calendar: LedgerCalendar) -> Bool {
        guard let last = lastPromptMonth, let lastKey = MonthKey(string: last) else { return true }
        return lastKey != MonthKey(date: now, calendar: calendar)
    }

    /// What to pre-fill: last month's goal, or $200 the first time.
    public static func prefillAmount(previousGoal: Decimal?) -> Decimal {
        guard let previous = previousGoal, previous >= 0 else { return defaultGoal }
        return previous
    }
}

/// The Monday "what did you earn last week?" reminder.
public enum EarningsReminder {
    public static let notificationTitle = "New week!"
    public static let notificationBody = "What did you earn last week?"

    /// Monday 00:00 of the week that just ended.
    public static func lastWeekStart(now: Date, calendar: LedgerCalendar) -> Date {
        calendar.lastCompletedWeekStart(now: now)
    }

    /// True when no earning is stored for the week that just ended (an entered amount of 0 counts as entered).
    public static func isLastWeekMissing(earnings: [WeeklyEarning], now: Date, calendar: LedgerCalendar) -> Bool {
        let target = calendar.lastCompletedWeekStart(now: now)
        return !earnings.contains { calendar.weekStart(for: $0.weekStart) == target }
    }

    /// Past weeks with no entry, oldest first, going back `weeksBack` completed weeks.
    public static func missingWeekStarts(earnings: [WeeklyEarning], now: Date, calendar: LedgerCalendar, weeksBack: Int = 4) -> [Date] {
        let entered = Set(earnings.map { calendar.weekStart(for: $0.weekStart) })
        let thisWeek = calendar.weekStart(for: now)
        guard weeksBack > 0 else { return [] }
        return (1...weeksBack).reversed()
            .map { calendar.startOfDay(thisWeek, addingDays: -7 * $0) }
            .filter { !entered.contains($0) }
    }

    /// Components for a repeating `UNCalendarNotificationTrigger`: every Monday at hour:minute local time.
    /// (`weekday` 2 = Monday in the Gregorian calendar.) Hour and minute are clamped to valid ranges.
    public static func weeklyTriggerComponents(hour: Int = 8, minute: Int = 0) -> DateComponents {
        var parts = DateComponents()
        parts.weekday = 2
        parts.hour = min(max(hour, 0), 23)
        parts.minute = min(max(minute, 0), 59)
        return parts
    }

    /// The next time the reminder fires strictly after `now`: today if it is Monday before hour:minute, otherwise next Monday.
    public static func nextReminderDate(after now: Date, hour: Int = 8, minute: Int = 0, calendar: LedgerCalendar) -> Date {
        let h = min(max(hour, 0), 23)
        let m = min(max(minute, 0), 59)
        var monday = calendar.weekStart(for: now)
        for _ in 0..<3 {
            let parts = calendar.calendar.dateComponents([.year, .month, .day], from: monday)
            var fire = DateComponents()
            fire.year = parts.year
            fire.month = parts.month
            fire.day = parts.day
            fire.hour = h
            fire.minute = m
            if let date = calendar.calendar.date(from: fire), date > now { return date }
            monday = calendar.startOfDay(monday, addingDays: 7)
        }
        return monday
    }

    /// Year/month/day/hour/minute (plus weekday 2) of `nextReminderDate`, for a one-off trigger.
    public static func nextReminderComponents(after now: Date, hour: Int = 8, minute: Int = 0, calendar: LedgerCalendar) -> DateComponents {
        let date = nextReminderDate(after: now, hour: hour, minute: minute, calendar: calendar)
        var parts = calendar.calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        parts.calendar = nil
        parts.timeZone = nil
        return parts
    }
}
