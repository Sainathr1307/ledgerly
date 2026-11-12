// CategoryTransactionsView.swift — drill-down from a chart: one category's transactions for one month.

import SwiftUI
import LedgerlyCore

struct CategoryTransactionsView: View {
    @Environment(LedgerStore.self) private var store
    let categoryID: UUID
    let month: MonthKey
    @State private var editing: TransactionRecord?

    var body: some View {
        content
            .navigationTitle(store.categoryName(for: categoryID))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { record in
                TransactionEditorSheet(store: store, editing: record)
            }
    }

    private var records: [TransactionRecord] {
        let calendar = store.calendar
        let inMonth = BudgetEngine.transactions(in: month, from: store.data.transactions, calendar: calendar)
        let categories = store.data.categories
        let matching = inMonth.filter { record in
            BudgetEngine.effectiveCategoryID(record.categoryID, categories: categories) == categoryID
        }
        return matching.sorted { $0.date > $1.date }
    }

    private var total: Decimal {
        var sum: Decimal = 0
        for record in records {
            sum += record.amount
        }
        return sum
    }

    @ViewBuilder
    private var content: some View {
        let rows = records
        if rows.isEmpty {
            EmptyStateView(
                title: "Nothing here",
                systemImage: "tray",
                message: "No transactions in this category for \(DateText.monthTitle(month, calendar: store.calendar))."
            )
            .frame(maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(rows) { record in
                        Button {
                            editing = record
                        } label: {
                            TransactionRow(
                                record: record,
                                category: store.category(for: record.categoryID),
                                showsDate: true
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the transaction for editing")
                    }
                } header: {
                    Text("\(DateText.monthTitle(month, calendar: store.calendar)) · \(Money.string(total))")
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}
