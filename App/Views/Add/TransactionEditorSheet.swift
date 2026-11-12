// TransactionEditorSheet.swift — quick add and edit: keypad first, then category, merchant, payment, date, notes.
// Save is pinned to the bottom so it is always reachable.

import SwiftUI
import LedgerlyCore

struct TransactionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: TransactionEditorModel
    @State private var rulePrompt: RulePrompt?
    @FocusState private var merchantFocused: Bool
    @FocusState private var notesFocused: Bool

    init(store: LedgerStore, editing: TransactionRecord?) {
        _model = State(initialValue: TransactionEditorModel(store: store, editing: editing))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                form
                if let rulePrompt {
                    promptOverlay(rulePrompt)
                }
            }
            .navigationTitle(model.isEditing ? "Edit Transaction" : "Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(rulePrompt != nil)
                    .accessibilityIdentifier("cancelTransactionButton")
                }
            }
        }
        .interactiveDismissDisabled(rulePrompt != nil)
        .task {
            await model.loadKnownMerchants()
        }
    }

    // MARK: - Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                amountHeader
                AmountKeypad(
                    onDigit: { digit in model.tapDigit(digit) },
                    onDot: { model.tapDot() },
                    onDelete: { model.tapDelete() }
                )
                categorySection
                merchantSection
                paymentSection
                detailsSection
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            saveBar
        }
        .accessibilityHidden(rulePrompt != nil)
    }

    private var amountHeader: some View {
        VStack(spacing: 6) {
            Text(model.amountDisplay)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(model.isRefund ? Color.green : Color.primary)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(model.isRefund ? "Refund amount" : "Amount")
                .accessibilityValue(model.amountDisplay)
                .accessibilityIdentifier("amountDisplay")
            Toggle("Refund", isOn: Bindable(model).isRefund)
                .font(.subheadline)
                .accessibilityHint("Saves the amount as money back, which lowers spending")
                .accessibilityIdentifier("refundToggle")
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Category")
            CategoryChipGrid(
                categories: model.categoryChoices,
                selectedID: model.categoryID,
                onPick: { id in model.pickCategory(id) }
            )
        }
    }

    private var merchantSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Merchant")
            MerchantEntry(
                merchant: Bindable(model).merchant,
                suggestions: model.merchantSuggestions,
                onPick: { name in
                    model.pickSuggestion(name)
                    merchantFocused = false
                },
                isFocused: $merchantFocused
            )
            .onChange(of: model.merchant) { _, _ in
                model.merchantChanged()
            }
            .onSubmit {
                merchantFocused = false
            }
        }
    }

    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Paid with")
            PaymentMethodRow(choices: model.paymentChoices, selection: Bindable(model).payment)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker(
                "Date & time",
                selection: Bindable(model).date,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("transactionDatePicker")
            TextField("Notes (optional)", text: Bindable(model).notes, axis: .vertical)
                .lineLimit(1...4)
                .focused($notesFocused)
                .padding(12)
                .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Notes")
                .accessibilityIdentifier("notesField")
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private var saveBar: some View {
        Button {
            save()
        } label: {
            Text(model.isEditing ? "Save Changes" : "Save")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!model.canSave)
        .accessibilityHint(model.canSave ? "Saves the transaction" : "Enter an amount first")
        .accessibilityIdentifier("saveTransactionButton")
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Rule prompt

    private func promptOverlay(_ prompt: RulePrompt) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            RulePromptCard(
                prompt: prompt,
                onAlways: {
                    Task {
                        await model.acceptRule(prompt)
                        dismiss()
                    }
                },
                onJustOnce: {
                    dismiss()
                }
            )
        }
    }

    // MARK: - Actions

    private func save() {
        merchantFocused = false
        notesFocused = false
        Task {
            let outcome = await model.save()
            if !outcome.saved {
                return
            }
            if let prompt = outcome.prompt {
                rulePrompt = prompt
            } else {
                dismiss()
            }
        }
    }
}
