#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

/// Where a transaction came from.
public enum SourceKind: String, Codable, CaseIterable, Sendable {
    case walletShortcut, financeKit, manual, csvImport

    /// Short human-readable label for filters and badges.
    public var displayName: String {
        switch self {
        case .walletShortcut: return "Wallet"
        case .financeKit: return "FinanceKit"
        case .manual: return "Manual"
        case .csvImport: return "Import"
        }
    }
}

/// How a purchase was paid for.
public enum PaymentMethod: Hashable, Codable, Sendable {
    case cash, otherCard, walletCard(String)

    /// "cash" | "otherCard" | "walletCard" — the string stored by the SwiftData mirror.
    public var kindRaw: String {
        switch self {
        case .cash: return "cash"
        case .otherCard: return "otherCard"
        case .walletCard: return "walletCard"
        }
    }

    /// The Wallet card name, only for `.walletCard`.
    public var cardName: String? {
        if case .walletCard(let name) = self { return name }
        return nil
    }

    /// Rebuilds a payment method from its stored parts. Unknown kinds fall back to `.otherCard`;
    /// a "walletCard" with a blank name also becomes `.otherCard`.
    public init(kindRaw: String, cardName: String?) {
        switch kindRaw {
        case "cash":
            self = .cash
        case "walletCard":
            let trimmed = (cardName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self = trimmed.isEmpty ? .otherCard : .walletCard(trimmed)
        default:
            self = .otherCard
        }
    }

    /// "Cash", "Other card", or the card name.
    public var displayName: String {
        switch self {
        case .cash: return "Cash"
        case .otherCard: return "Other card"
        case .walletCard(let name): return name
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, cardName }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let name = try container.decodeIfPresent(String.self, forKey: .cardName)
        self.init(kindRaw: kind, cardName: name)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kindRaw, forKey: .kind)
        try container.encodeIfPresent(cardName, forKey: .cardName)
    }
}

/// One purchase or refund.
public struct TransactionRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    /// > 0 expense, < 0 refund.
    public var amount: Decimal
    public var currencyCode: String
    public var merchant: String
    public var categoryID: UUID?
    public var date: Date
    public var paymentMethod: PaymentMethod
    public var source: SourceKind
    public var notes: String
    public var needsReview: Bool
    public var isPossibleDuplicate: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        amount: Decimal,
        currencyCode: String = "USD",
        merchant: String,
        categoryID: UUID? = nil,
        date: Date,
        paymentMethod: PaymentMethod = .cash,
        source: SourceKind = .manual,
        notes: String = "",
        needsReview: Bool = false,
        isPossibleDuplicate: Bool = false,
        createdAt: Date
    ) {
        self.id = id
        self.amount = amount
        self.currencyCode = currencyCode
        self.merchant = merchant
        self.categoryID = categoryID
        self.date = date
        self.paymentMethod = paymentMethod
        self.source = source
        self.notes = notes
        self.needsReview = needsReview
        self.isPossibleDuplicate = isPossibleDuplicate
        self.createdAt = createdAt
    }

    /// True for refunds (negative amounts).
    public var isRefund: Bool { amount < 0 }
}

/// A spending category.
public struct CategoryRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    /// "#RRGGBB"
    public var colorHex: String
    /// SF Symbol name.
    public var symbolName: String
    public var sortOrder: Int
    public var isArchived: Bool
    /// food, groceries, gas, shopping, recreation, bills, transportation, health, subscriptions, other; nil for user-made.
    public var systemKey: String?

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        symbolName: String,
        sortOrder: Int,
        isArchived: Bool = false,
        systemKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.systemKey = systemKey
    }

    /// Food & Dining, Shopping, Recreation, Subscriptions and every user-made category.
    /// These are the only categories a gap-closing plan may cut.
    public var isDiscretionary: Bool {
        guard let key = systemKey else { return true }
        return CategoryRecord.discretionaryKeys.contains(key)
    }

    /// Bills & Utilities and Health — never part of a cut list.
    public var isProtected: Bool {
        guard let key = systemKey else { return false }
        return key == "bills" || key == "health"
    }

    /// System keys of the built-in discretionary categories, in gap-plan cut order.
    public static let discretionaryKeys: [String] = ["food", "shopping", "recreation", "subscriptions"]
}

/// The ten built-in categories. IDs are fixed so data written by different builds lines up.
public enum DefaultCategories {
    public static let all: [CategoryRecord] = [
        make("food", 1, "Food & Dining", "#E8590C", "fork.knife", 0),
        make("groceries", 2, "Groceries", "#2F9E44", "cart.fill", 1),
        make("gas", 3, "Gas", "#E03131", "fuelpump.fill", 2),
        make("shopping", 4, "Shopping", "#7048E8", "bag.fill", 3),
        make("recreation", 5, "Recreation & Entertainment", "#D6336C", "gamecontroller.fill", 4),
        make("bills", 6, "Bills & Utilities", "#F59F00", "bolt.fill", 5),
        make("transportation", 7, "Transportation", "#1C7ED6", "car.fill", 6),
        make("health", 8, "Health", "#0CA678", "cross.case.fill", 7),
        make("subscriptions", 9, "Subscriptions", "#AE3EC9", "repeat", 8),
        make("other", 10, "Other", "#868E96", "ellipsis.circle.fill", 9)
    ]

    /// All system keys in default order.
    public static let systemKeys: [String] = [
        "food", "groceries", "gas", "shopping", "recreation", "bills", "transportation", "health", "subscriptions", "other"
    ]

    /// Fixed id of a default category. Unknown keys return the id of "other".
    public static func id(_ systemKey: String) -> UUID {
        if let index = systemKeys.firstIndex(of: systemKey) { return uuid(index + 1) }
        return uuid(10)
    }

    /// The default record for a system key, if the key is known.
    public static func category(_ systemKey: String) -> CategoryRecord? {
        all.first { $0.systemKey == systemKey }
    }

    /// Id of the "Other" category.
    public static var otherID: UUID { uuid(10) }

    private static func uuid(_ n: Int) -> UUID {
        let hex = String(n, radix: 16, uppercase: true)
        let tail = String(repeating: "0", count: 12 - hex.count) + hex
        // The literal below is a valid UUID, so the fallback is never reached.
        return UUID(uuidString: "4C454447-4552-4C59-8000-\(tail)") ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(n)))
    }

    private static func make(_ key: String, _ n: Int, _ name: String, _ color: String, _ symbol: String, _ order: Int) -> CategoryRecord {
        CategoryRecord(id: uuid(n), name: name, colorHex: color, symbolName: symbol, sortOrder: order, isArchived: false, systemKey: key)
    }
}

/// A learned "always categorize this merchant as…" rule. `normalizedMerchant` is `MerchantNormalizer.normalize` output.
public struct MerchantRule: Hashable, Codable, Sendable {
    public var normalizedMerchant: String
    public var categoryID: UUID

    public init(normalizedMerchant: String, categoryID: UUID) {
        self.normalizedMerchant = normalizedMerchant
        self.categoryID = categoryID
    }
}

/// Earnings for one Monday–Sunday week. `weekStart` is Monday 00:00 local time.
public struct WeeklyEarning: Hashable, Codable, Sendable {
    public var weekStart: Date
    public var amount: Decimal

    public init(weekStart: Date, amount: Decimal) {
        self.weekStart = weekStart
        self.amount = amount
    }
}

/// A calendar month (Gregorian).
public struct MonthKey: Hashable, Comparable, Codable, Sendable {
    public var year: Int
    public var month: Int

    /// Out-of-range months are carried into the year (month 13 → January of next year, month 0 → December of the previous one).
    public init(year: Int, month: Int) {
        let zeroBased = year * 12 + (month - 1)
        let y = Int((Double(zeroBased) / 12).rounded(.down))
        self.year = y
        self.month = zeroBased - y * 12 + 1
    }

    public init(date: Date, calendar: LedgerCalendar) {
        let parts = calendar.calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1)
    }

    public var previous: MonthKey { MonthKey(year: year, month: month - 1) }
    public var next: MonthKey { MonthKey(year: year, month: month + 1) }

    /// The month `count` months later (negative = earlier).
    public func adding(months count: Int) -> MonthKey { MonthKey(year: year, month: month + count) }

    /// "yyyy-MM", e.g. "2026-03". This is the format `AppSettings.lastGoalPromptMonth` uses.
    public var stringValue: String {
        let y = String(year)
        let paddedYear = String(repeating: "0", count: max(0, 4 - y.count)) + y
        return paddedYear + "-" + (month < 10 ? "0" : "") + String(month)
    }

    /// Parses "yyyy-MM". Returns nil for anything else.
    public init?(string: String) {
        let parts = string.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m), y >= 0 else { return nil }
        self.init(year: y, month: m)
    }

    public static func < (lhs: MonthKey, rhs: MonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

/// The savings goal for one month.
public struct MonthlyGoal: Hashable, Codable, Sendable {
    public var month: MonthKey
    public var amount: Decimal

    public init(month: MonthKey, amount: Decimal) {
        self.month = month
        self.amount = amount
    }
}
