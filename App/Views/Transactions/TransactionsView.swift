// TransactionsView.swift — the Transactions tab: day-grouped list, search, filters, swipe to edit/delete with undo.

import SwiftUI
import LedgerlyCore

struct TransactionsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var model = TransactionsListModel()
    @State private var editing: TransactionRecord?
    @State private var isFilterSheetPresented = false

    private var router: AppRouter { AppRouter.shared }

    var body: some View {
        NavigationStack {
            listOrEmptyState
                .navigationTitle("Transactions")
                .searchable(text: Bindable(model).searchText, prompt: "Merchant or notes")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        filterButton
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    undoBanner
                }
        }
        .sheet(item: $editing) { record in
            TransactionEditorSheet(store: store, editing: record)
        }
        .sheet(isPresented: $isFilterSheetPresented) {
            TransactionFilterSheet(model: model)
        }
    }

    private var groups: [IndexedDayGroup] {
        model.groups(
            transactions: store.data.transactions,
            categories: store.data.categories,
            calendar: store.calendar
        )
    }

    @ViewBuilder
    private var listOrEmptyState: some View {
        let visibleGroups = groups
        if store.data.transactions.isEmpty {
            EmptyStateView(
                title: "No transactions yet",
                systemImage: "tray",
                message: "Tap + to add your first purchase. It takes a few seconds.",
                actionTitle: "Add a transaction",
                action: { router.isAddSheetPresented = true }
            )
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("transactionsEmptyState")
        } else if visibleGroups.isEmpty {
            EmptyStateView(
                title: "No matches",
                systemImage: "magnifyingglass",
                message: "Nothing fits the current search and filters.",
                actionTitle: model.hasActiveFilters ? "Clear filters" : nil,
                action: { model.resetFilters() }
            )
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("transactionsNoResults")
        } else {
            TransactionDayList(
                groups: visibleGroups,
                onEdit: { record in editing = record },
                onDelete: { record in
                    withAnimation {
                        model.delete(record, store: store)
                    }
                }
            )
        }
    }

    private var filterButton: some View {
        Button {
            isFilterSheetPresented = true
        } label: {
            Image(systemName: model.hasActiveFilters
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filters")
        .accessibilityValue(model.hasActiveFilters ? "\(model.activeFilterCount) active" : "None active")
        .accessibilityIdentifier("filterButton")
    }

    @ViewBuilder
    private var undoBanner: some View {
        if let deleted = model.pendingUndo {
            UndoBanner(message: undoMessage(for: deleted)) {
                withAnimation {
                    model.undo(store: store)
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func undoMessage(for record: TransactionRecord) -> String {
        let name = MerchantNormalizer.isBlank(record.merchant) ? "Transaction" : record.merchant
        return "Deleted \(name), \(Money.string(record.amount))"
    }
}

/// The grouped list itself.
struct TransactionDayList: View {
    @Environment(LedgerStore.self) private var store
    let groups: [IndexedDayGroup]
    let onEdit: (TransactionRecord) -> Void
    let onDelete: (TransactionRecord) -> Void

    var body: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        rowView(row)
                    }
                } header: {
                    header(for: group)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func header(for group: IndexedDayGroup) -> some View {
        HStack {
            Text(DateText.day(group.day))
            Spacer()
            Text(Money.string(group.total))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(DateText.day(group.day)), total \(Money.string(group.total))")
    }

    private func rowView(_ row: IndexedTransaction) -> some View {
        Button {
            onEdit(row.record)
        } label: {
            TransactionRow(record: row.record, category: store.category(for: row.record.categoryID))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the transaction for editing")
        .accessibilityIdentifier("transaction_row_\(row.index)")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete(row.record)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                onEdit(row.record)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}
