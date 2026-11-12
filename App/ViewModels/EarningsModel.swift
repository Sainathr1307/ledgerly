// EarningsModel.swift — the weekly earnings screen: recent Monday–Sunday weeks, newest first, each editable.

import Foundation
import Observation
import LedgerlyCore

/// One week on the earnings screen.
struct EarningsWeekRow: Identifiable {
    let weekStart: Date
    let rangeText: String
    /// What is stored for the week (nil = not entered).
    let savedAmount: Decimal?
    /// What is in the text field.
    var text: String
    var id: Date { weekStart }
}

@MainActor
@Observable
final class EarningsModel {
    /// How many completed weeks are listed (about half a year).
    static let weekCount = 26

    var rows: [EarningsWeekRow] = []
    var isSaving: Bool = false
    private let store: LedgerStore

    init(store: LedgerStore) {
        self.store = store
        self.rows = EarningsModel.makeRows(store: store)
    }

    private static func makeRows(store: LedgerStore) -> [EarningsWeekRow] {
        let calendar = store.calendar
        let now = Date()
        // Later entries win when two land in the same week, like in the engines.
        var saved: [Date: Decimal] = [:]
        for earning in store.data.earnings {
            saved[calendar.weekStart(for: earning.weekStart)] = earning.amount
        }
        var result: [EarningsWeekRow] = []
        var weekStart = calendar.lastCompletedWeekStart(now: now)
        for _ in 0..<weekCount {
            let amount = saved[weekStart]
            let text = amount.map { Money.fieldText($0) } ?? ""
            result.append(
                EarningsWeekRow(
                    weekStart: weekStart,
                    rangeText: DateText.weekRange(weekStart: weekStart, calendar: calendar),
                    savedAmount: amount,
                    text: text
                )
            )
            // Step back one week by calendar days (never by seconds), so daylight saving changes are handled.
            weekStart = calendar.weekStart(for: calendar.date(byAddingDays: -7, to: weekStart))
        }
        return result
    }

    /// The typed amount for a row: nil when blank, unreadable or negative.
    func parsedAmount(for row: EarningsWeekRow) -> Decimal? {
        guard let value = AmountParser.parse(row.text), value >= 0 else {
            return nil
        }
        return value
    }

    func isBlank(_ row: EarningsWeekRow) -> Bool {
        row.text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// True when a row has text that cannot be read as an amount.
    func isInvalid(_ row: EarningsWeekRow) -> Bool {
        !isBlank(row) && parsedAmount(for: row) == nil
    }

    var hasInvalidRows: Bool {
        rows.contains { isInvalid($0) }
    }

    var hasChanges: Bool {
        rows.contains { row in
            if isBlank(row) {
                return row.savedAmount != nil
            }
            return parsedAmount(for: row) != row.savedAmount
        }
    }

    /// Writes every changed week: a typed amount is saved, a cleared field removes the entry.
    func save() async {
        isSaving = true
        for row in rows {
            if isBlank(row) {
                if row.savedAmount != nil {
                    await store.deleteEarning(weekStart: row.weekStart)
                }
            } else if let amount = parsedAmount(for: row), amount != row.savedAmount {
                await store.setEarning(weekStart: row.weekStart, amount: amount)
            }
        }
        await store.reload()
        isSaving = false
    }
}
