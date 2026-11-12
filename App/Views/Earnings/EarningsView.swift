// EarningsView.swift — enter or edit weekly earnings. Weeks run Monday to Sunday; last week is first.

import SwiftUI
import LedgerlyCore

struct EarningsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: EarningsModel

    init(store: LedgerStore) {
        _model = State(initialValue: EarningsModel(store: store))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.rows.indices, id: \.self) { index in
                        EarningsWeekField(
                            row: model.rows[index],
                            index: index,
                            isInvalid: model.isInvalid(model.rows[index]),
                            text: textBinding(for: index)
                        )
                    }
                } header: {
                    Text("Weeks (Monday – Sunday)")
                } footer: {
                    Text("Each week counts toward the month its Monday falls in. Clear a field to remove that week's entry.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Weekly Earnings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .accessibilityIdentifier("closeEarningsButton")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                saveBar
            }
        }
    }

    private func textBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                index < model.rows.count ? model.rows[index].text : ""
            },
            set: { newValue in
                if index < model.rows.count {
                    model.rows[index].text = newValue
                }
            }
        )
    }

    private var saveBar: some View {
        Button {
            Task {
                await model.save()
                dismiss()
            }
        } label: {
            Text("Save earnings")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!model.hasChanges || model.hasInvalidRows || model.isSaving)
        .accessibilityIdentifier("saveEarningsButton")
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// One week: its date range and an amount field.
private struct EarningsWeekField: View {
    let row: EarningsWeekRow
    let index: Int
    let isInvalid: Bool
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.rangeText)
                    .font(.body)
                if index == 0 {
                    Text(row.savedAmount == nil ? "Last week · not entered yet" : "Last week")
                        .font(.caption)
                        .foregroundStyle(row.savedAmount == nil ? Color.orange : Color.secondary)
                } else if row.savedAmount == nil {
                    Text("Not entered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isInvalid {
                    Text("Not a valid amount")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 8)
            Text(Money.symbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 70, maxWidth: 120)
                .accessibilityLabel("Earnings for \(row.rangeText)")
                .accessibilityIdentifier("earningsField_\(index)")
        }
        .listRowBackground(highlight)
    }

    private var highlight: Color {
        if index == 0 && row.savedAmount == nil {
            return Color.orange.opacity(0.15)
        }
        return Color(uiColor: .secondarySystemGroupedBackground)
    }
}
