// TransactionsListModel.swift — search, filters and delete-with-undo for the Transactions tab.

import Foundation
import Observation
import LedgerlyCore

/// A transaction with its position in the visible list (used for accessibility identifiers).
struct IndexedTransaction: Identifiable {
    let index: Int
    let record: TransactionRecord
    var id: UUID { record.id }
}

/// One day of the list with its total.
struct IndexedDayGroup: Identifiable {
    let day: Date
    let total: Decimal
    let rows: [IndexedTransaction]
    var id: Date { day }
}

@MainActor
@Observable
final class TransactionsListModel {
    var searchText: String = ""

    // Filter sheet state.
    var categoryIDs: Set<UUID> = []
    var sources: Set<SourceKind> = []
    var paymentMethods: Set<PaymentMethod> = []
    var limitDates: Bool = false
    var fromDate: Date = Date()
    var toDate: Date = Date()
    var needsReviewOnly: Bool = false

    /// The transaction that was just deleted and can still be put back.
    private(set) var pendingUndo: TransactionRecord?
    private var undoToken: Int = 0

    var hasActiveFilters: Bool {
        !categoryIDs.isEmpty || !sources.isEmpty || !paymentMethods.isEmpty || limitDates || needsReviewOnly
    }

    var activeFilterCount: Int {
        var count = 0
        if !categoryIDs.isEmpty { count += 1 }
        if !sources.isEmpty { count += 1 }
        if !paymentMethods.isEmpty { count += 1 }
        if limitDates { count += 1 }
        if needsReviewOnly { count += 1 }
        return count
    }

    func resetFilters() {
        categoryIDs = []
        sources = []
        paymentMethods = []
        limitDates = false
        needsReviewOnly = false
    }

    func filter(calendar: LedgerCalendar) -> TransactionFilter {
        var filter = TransactionFilter(
            searchText: searchText,
            categoryIDs: categoryIDs,
            sources: sources,
            paymentMethods: paymentMethods,
            needsReviewOnly: needsReviewOnly
        )
        if limitDates {
            let first = min(fromDate, toDate)
            let last = max(fromDate, toDate)
            filter.setDayRange(from: first, through: last, calendar: calendar)
        }
        return filter
    }

    /// The visible list: filtered, grouped by day (newest first), each row numbered from 0.
    func groups(transactions: [TransactionRecord], categories: [CategoryRecord], calendar: LedgerCalendar) -> [IndexedDayGroup] {
        let visible = ChartData.filter(transactions, with: filter(calendar: calendar), categories: categories)
        let dayGroups = ChartData.groupByDay(visible, calendar: calendar)
        var result: [IndexedDayGroup] = []
        var index = 0
        for group in dayGroups {
            var rows: [IndexedTransaction] = []
            for record in group.transactions {
                rows.append(IndexedTransaction(index: index, record: record))
                index += 1
            }
            result.append(IndexedDayGroup(day: group.day, total: group.total, rows: rows))
        }
        return result
    }

    // MARK: - Delete with undo

    func delete(_ record: TransactionRecord, store: LedgerStore) {
        undoToken += 1
        let token = undoToken
        pendingUndo = record
        Task {
            await store.deleteTransaction(id: record.id)
            try? await Task.sleep(for: .seconds(6))
            if token == self.undoToken {
                self.pendingUndo = nil
            }
        }
    }

    func undo(store: LedgerStore) {
        guard let record = pendingUndo else {
            return
        }
        undoToken += 1
        pendingUndo = nil
        Task {
            await store.saveTransaction(record)
        }
    }
}
