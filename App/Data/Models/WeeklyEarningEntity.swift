// WeeklyEarningEntity.swift — SwiftData mirror of LedgerlyCore.WeeklyEarning (one amount per Monday-based week).

import Foundation
import SwiftData

@Model
final class WeeklyEarningEntity {
    /// Monday 00:00 local time of the week; the natural key.
    @Attribute(.unique) var weekStart: Date = Date(timeIntervalSinceReferenceDate: 0)
    var amount: Decimal = Decimal(0)

    init(weekStart: Date = Date(timeIntervalSinceReferenceDate: 0), amount: Decimal = Decimal(0)) {
        self.weekStart = weekStart
        self.amount = amount
    }
}
