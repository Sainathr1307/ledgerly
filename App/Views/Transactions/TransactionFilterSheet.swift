// TransactionFilterSheet.swift — filters for the Transactions tab: category, source, payment method, date range.

import SwiftUI
import LedgerlyCore

struct TransactionFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LedgerStore.self) private var store
    let model: TransactionsListModel

    var body: some View {
        NavigationStack {
            Form {
                categorySection
                sourceSection
                paymentSection
                dateSection
                reviewSection
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        model.resetFilters()
                    }
                    .disabled(!model.hasActiveFilters)
                    .accessibilityIdentifier("resetFiltersButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("filterDoneButton")
                }
            }
        }
    }

    private var categorySection: some View {
        Section("Category") {
            ForEach(store.data.categories) { category in
                FilterCheckRow(
                    title: category.isArchived ? category.name + " (archived)" : category.name,
                    isOn: model.categoryIDs.contains(category.id)
                ) {
                    toggleCategory(category.id)
                }
            }
        }
    }

    private var sourceSection: some View {
        Section("Source") {
            ForEach(SourceKind.allCases, id: \.self) { source in
                FilterCheckRow(title: source.displayName, isOn: model.sources.contains(source)) {
                    toggleSource(source)
                }
            }
        }
    }

    @ViewBuilder
    private var paymentSection: some View {
        let methods = ChartData.paymentMethods(in: store.data.transactions)
        if !methods.isEmpty {
            Section("Payment method") {
                ForEach(methods, id: \.self) { method in
                    FilterCheckRow(title: method.displayName, isOn: model.paymentMethods.contains(method)) {
                        togglePayment(method)
                    }
                }
            }
        }
    }

    private var dateSection: some View {
        Section("Date range") {
            Toggle("Limit to dates", isOn: Bindable(model).limitDates)
            if model.limitDates {
                DatePicker("From", selection: Bindable(model).fromDate, displayedComponents: [.date])
                DatePicker("Through", selection: Bindable(model).toDate, displayedComponents: [.date])
            }
        }
    }

    private var reviewSection: some View {
        Section {
            Toggle("Needs review only", isOn: Bindable(model).needsReviewOnly)
        }
    }

    private func toggleCategory(_ id: UUID) {
        if model.categoryIDs.contains(id) {
            model.categoryIDs.remove(id)
        } else {
            model.categoryIDs.insert(id)
        }
    }

    private func toggleSource(_ source: SourceKind) {
        if model.sources.contains(source) {
            model.sources.remove(source)
        } else {
            model.sources.insert(source)
        }
    }

    private func togglePayment(_ method: PaymentMethod) {
        if model.paymentMethods.contains(method) {
            model.paymentMethods.remove(method)
        } else {
            model.paymentMethods.insert(method)
        }
    }
}

/// A row with a checkmark that toggles on tap.
private struct FilterCheckRow: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
