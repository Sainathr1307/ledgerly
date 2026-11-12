// NeedsReviewView.swift — the Needs Review inbox: transactions the Wallet automation logged with a zero
// amount or blank merchant, and possible duplicates. One tap opens the editor to fix an item.

import SwiftUI
import LedgerlyCore

struct NeedsReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LedgerStore.self) private var store
    @State private var editing: TransactionRecord?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Needs Review")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                        .accessibilityIdentifier("reviewDoneButton")
                    }
                }
        }
        .sheet(item: $editing) { record in
            TransactionEditorSheet(store: store, editing: record)
        }
    }

    @ViewBuilder
    private var content: some View {
        let items = store.reviewItems
        if items.isEmpty {
            EmptyStateView(
                title: "All caught up",
                systemImage: "checkmark.circle",
                message: "Transactions that arrive with a missing amount or merchant, and possible duplicates, wait here."
            )
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("reviewEmptyState")
        } else {
            List {
                Section {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, record in
                        row(record, index: index)
                    }
                } footer: {
                    Text("Tap an item to fix it. Swipe for Keep or Delete.")
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func row(_ record: TransactionRecord, index: Int) -> some View {
        Button {
            editing = record
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                TransactionRow(
                    record: record,
                    category: store.category(for: record.categoryID),
                    showsDate: true
                )
                Text(reason(for: record))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the transaction so you can fix it")
        .accessibilityIdentifier("review_row_\(index)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                delete(record)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                keep(record)
            } label: {
                Label("Keep", systemImage: "checkmark")
            }
            .tint(.green)
        }
        .contextMenu {
            Button {
                keep(record)
            } label: {
                Label("Keep as is", systemImage: "checkmark")
            }
            Button(role: .destructive) {
                delete(record)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func reason(for record: TransactionRecord) -> String {
        var reasons: [String] = []
        if record.amount == 0 {
            reasons.append("the amount is missing")
        }
        if MerchantNormalizer.isBlank(record.merchant) {
            reasons.append("the merchant is missing")
        }
        if record.isPossibleDuplicate {
            reasons.append("it looks like a duplicate")
        }
        if reasons.isEmpty {
            return "Flagged for review."
        }
        return "Flagged because " + reasons.joined(separator: " and ") + "."
    }

    /// Keeps the transaction as it is and clears its flags.
    private func keep(_ record: TransactionRecord) {
        var updated = record
        updated.needsReview = false
        updated.isPossibleDuplicate = false
        let kept = updated
        Task {
            await store.saveTransaction(kept)
        }
    }

    private func delete(_ record: TransactionRecord) {
        Task {
            await store.deleteTransaction(id: record.id)
        }
    }
}
