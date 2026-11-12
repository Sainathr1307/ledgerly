// GoalSheet.swift — "How much do you want to save this month?" Shown on first launch, on the first open of
// each month, and whenever the user wants to change the goal.

import SwiftUI
import LedgerlyCore

struct GoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let store: LedgerStore
    private let isMonthlyPrompt: Bool
    @State private var amountText: String
    @FocusState private var fieldFocused: Bool

    init(store: LedgerStore, isMonthlyPrompt: Bool) {
        self.store = store
        self.isMonthlyPrompt = isMonthlyPrompt
        _amountText = State(initialValue: Money.fieldText(store.goalPrefill()))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("How much do you want to save this month?")
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    amountField
                    if parsedAmount == nil {
                        Text("Enter an amount of 0 or more.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    saveButton
                }
                .padding(20)
            }
            .navigationTitle(monthTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isMonthlyPrompt ? "Not now" : "Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("dismissGoalButton")
                }
            }
        }
        .onAppear {
            fieldFocused = true
        }
    }

    private var monthTitle: String {
        let calendar = store.calendar
        return DateText.monthTitle(MonthKey(date: Date(), calendar: calendar), calendar: calendar)
    }

    private var explanation: String {
        if isMonthlyPrompt {
            return "It starts with last month's goal. If you skip this, that amount is kept. You can change it any time in Settings."
        }
        return "Ledgerly uses this to work out your safe-to-spend number and where to cut back."
    }

    private var amountField: some View {
        HStack(spacing: 8) {
            Text(Money.symbol)
                .font(.title.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("200", text: $amountText)
                .font(.title.weight(.semibold))
                .keyboardType(.decimalPad)
                .focused($fieldFocused)
                .accessibilityLabel("Monthly savings goal")
                .accessibilityIdentifier("goalField")
            if !amountText.isEmpty {
                Button {
                    amountText = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear amount")
                .accessibilityIdentifier("goalClearButton")
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("Save goal")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(parsedAmount == nil)
        .accessibilityIdentifier("saveGoalButton")
    }

    /// The typed goal, or nil when it is blank, unreadable or negative.
    private var parsedAmount: Decimal? {
        guard let value = AmountParser.parse(amountText), value >= 0 else {
            return nil
        }
        return value
    }

    private func save() {
        guard let amount = parsedAmount else {
            return
        }
        let calendar = store.calendar
        let now = Date()
        let month = MonthKey(date: now, calendar: calendar)
        AppSettings.shared.lastGoalPromptMonth = GoalPrompt.monthString(now: now, calendar: calendar)
        Task {
            await store.setGoal(amount, for: month)
            dismiss()
        }
    }
}
