#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif
import XCTest
@testable import LedgerlyCore

/// Shared fixtures. Everything is pinned to America/Chicago and en_US so results do not depend on the machine.
enum T {
    static var chicago: LedgerCalendar { LedgerCalendar(timeZone: TimeZone(identifier: "America/Chicago")!) }
    static var utc: LedgerCalendar { LedgerCalendar(timeZone: TimeZone(identifier: "UTC")!) }
    static var us: Locale { Locale(identifier: "en_US") }
    static var categories: [CategoryRecord] { DefaultCategories.all }

    static func d(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0, calendar: LedgerCalendar = T.chicago) -> Date {
        calendar.date(year: year, month: month, day: day, hour: hour, minute: minute, second: second)!
    }

    static func id(_ key: String) -> UUID { DefaultCategories.id(key) }

    static func tx(
        _ amount: String, _ merchant: String = "Test", _ category: String? = "other",
        on date: Date, method: PaymentMethod = .cash, source: SourceKind = .manual, notes: String = "", needsReview: Bool = false
    ) -> TransactionRecord {
        TransactionRecord(
            amount: d(amount), merchant: merchant, categoryID: category.map { id($0) }, date: date,
            paymentMethod: method, source: source, notes: notes, needsReview: needsReview, createdAt: date
        )
    }

    static func earning(_ amount: String, weekOf date: Date, calendar: LedgerCalendar = T.chicago) -> WeeklyEarning {
        WeeklyEarning(weekStart: calendar.weekStart(for: date), amount: d(amount))
    }

    static func snapshot(
        _ month: MonthKey, now: Date, _ transactions: [TransactionRecord] = [], earnings: [WeeklyEarning] = [],
        goal: String = "200", categories: [CategoryRecord] = T.categories, calendar: LedgerCalendar = T.chicago
    ) -> BudgetSnapshot {
        BudgetEngine.snapshot(month: month, now: now, transactions: transactions, earnings: earnings, goal: d(goal), categories: categories, calendar: calendar)
    }
}
