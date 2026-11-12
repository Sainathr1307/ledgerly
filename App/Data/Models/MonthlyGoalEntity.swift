// MonthlyGoalEntity.swift — SwiftData mirror of LedgerlyCore.MonthlyGoal (one savings goal per month).

import Foundation
import SwiftData

@Model
final class MonthlyGoalEntity {
    /// "yyyy-MM", e.g. "2026-03"; the natural key. Build it with MonthlyGoalEntity.makeKey.
    @Attribute(.unique) var key: String = ""
    var year: Int = 0
    var month: Int = 0
    var amount: Decimal = Decimal(0)

    init(year: Int = 0, month: Int = 0, amount: Decimal = Decimal(0)) {
        self.key = MonthlyGoalEntity.makeKey(year: year, month: month)
        self.year = year
        self.month = month
        self.amount = amount
    }

    /// "yyyy-MM" with zero padding, so keys also sort correctly as strings.
    static func makeKey(year: Int, month: Int) -> String {
        let yearText = String(year)
        let monthText = String(month)
        let paddedYear = String(repeating: "0", count: max(0, 4 - yearText.count)) + yearText
        let paddedMonth = String(repeating: "0", count: max(0, 2 - monthText.count)) + monthText
        return paddedYear + "-" + paddedMonth
    }
}
