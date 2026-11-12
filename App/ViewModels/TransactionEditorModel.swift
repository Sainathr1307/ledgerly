// TransactionEditorModel.swift — state and rules for the quick-add / edit sheet.

import Foundation
import Observation
import LedgerlyCore

/// "Always categorize [merchant] as [category]?" — what the sheet asks after a category change.
struct RulePrompt: Equatable {
    var merchant: String
    var categoryID: UUID
    var categoryName: String
}

@MainActor
@Observable
final class TransactionEditorModel {
    /// The transaction being edited; nil when adding a new one.
    let original: TransactionRecord?

    /// The amount as typed on the keypad, e.g. "12.5". Always uses "." and has no sign.
    var amountText: String = ""
    var merchant: String = ""
    var categoryID: UUID?
    var payment: PaymentMethod = .cash
    var date: Date = Date()
    var notes: String = ""
    var isRefund: Bool = false
    var knownMerchants: [String] = []
    var isSaving: Bool = false

    /// While true, typing a merchant picks the category automatically.
    private var autoCategorize: Bool = true
    /// True once the user has tapped a category chip in this session.
    private var userPickedCategory: Bool = false
    private let originalCategoryID: UUID?

    private let store: LedgerStore

    init(store: LedgerStore, editing: TransactionRecord?) {
        // Constants first, so every later assignment happens on a fully initialized object.
        let effectiveCategoryID: UUID? = editing.flatMap { store.category(for: $0.categoryID)?.id }
        self.store = store
        self.original = editing
        self.originalCategoryID = effectiveCategoryID

        if let editing {
            categoryID = effectiveCategoryID
            let magnitude: Decimal = editing.amount < 0 ? -editing.amount : editing.amount
            if magnitude != 0 {
                amountText = MoneyFormat.plain(magnitude)
            }
            merchant = editing.merchant
            payment = editing.paymentMethod
            date = editing.date
            notes = editing.notes
            isRefund = editing.amount < 0
            // Keep the existing category unless the merchant was blank (a Needs Review item).
            autoCategorize = MerchantNormalizer.isBlank(editing.merchant)
        } else {
            let categorizer = Categorizer(rules: store.data.rules, categories: store.data.categories)
            categoryID = categorizer.fallbackCategoryID
        }
    }

    var isEditing: Bool { original != nil }

    // MARK: - Amount keypad

    var parsedAmount: Decimal {
        AmountParser.parse(amountText, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    var canSave: Bool {
        parsedAmount != 0 && !isSaving
    }

    /// The big amount at the top, e.g. "$12.5" while typing or "-$12.50" for a refund.
    var amountDisplay: String {
        let typed = amountText.isEmpty ? "0" : amountText
        let sign = isRefund ? "-" : ""
        return sign + Money.symbol + typed
    }

    func tapDigit(_ digit: Int) {
        let character = String(digit)
        if let dotIndex = amountText.firstIndex(of: ".") {
            let fractionDigits = amountText.distance(from: dotIndex, to: amountText.endIndex) - 1
            if fractionDigits >= 2 {
                return
            }
            amountText += character
            return
        }
        if amountText.count >= 9 {
            return
        }
        if amountText == "0" {
            amountText = character
        } else {
            amountText += character
        }
    }

    func tapDot() {
        if amountText.contains(".") {
            return
        }
        amountText = amountText.isEmpty ? "0." : amountText + "."
    }

    func tapDelete() {
        if !amountText.isEmpty {
            amountText.removeLast()
        }
    }

    // MARK: - Category and merchant

    /// Categories shown as chips: the active ones, plus the current one if it has been archived.
    var categoryChoices: [CategoryRecord] {
        var choices = store.activeCategories
        if let categoryID, !choices.contains(where: { $0.id == categoryID }) {
            if let current = store.data.categories.first(where: { $0.id == categoryID }) {
                choices.append(current)
            }
        }
        return choices
    }

    func pickCategory(_ id: UUID) {
        categoryID = id
        autoCategorize = false
        userPickedCategory = true
    }

    /// Called whenever the merchant text changes: re-run the categorizer until the user picks a chip.
    func merchantChanged() {
        guard autoCategorize else {
            return
        }
        let categorizer = Categorizer(rules: store.data.rules, categories: store.data.categories)
        categoryID = categorizer.categorize(merchant: merchant).categoryID
    }

    var merchantSuggestions: [String] {
        let suggestions = ChartData.merchantSuggestions(prefix: merchant, from: knownMerchants, limit: 6)
        let typed = MerchantNormalizer.searchKey(merchant).trimmingCharacters(in: .whitespaces)
        return suggestions.filter { MerchantNormalizer.searchKey($0) != typed }
    }

    func pickSuggestion(_ name: String) {
        merchant = name
        merchantChanged()
    }

    func loadKnownMerchants() async {
        knownMerchants = await store.knownMerchants()
    }

    // MARK: - Payment method

    /// Cash, Other card, then every Wallet card seen so far (and the current one when editing).
    var paymentChoices: [PaymentMethod] {
        var choices: [PaymentMethod] = [.cash, .otherCard]
        for card in store.knownWalletCards where !choices.contains(card) {
            choices.append(card)
        }
        if !choices.contains(payment) {
            choices.append(payment)
        }
        return choices
    }

    // MARK: - Saving

    /// Saves the transaction. Returns the "always categorize" question to ask, if any.
    func save() async -> (saved: Bool, prompt: RulePrompt?) {
        guard canSave else {
            return (false, nil)
        }
        isSaving = true
        let moment = Date()
        let magnitude = parsedAmount
        let signedAmount: Decimal = isRefund ? -magnitude : magnitude
        let cleanMerchant = MerchantNormalizer.displayName(merchant)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        var record: TransactionRecord
        if let original {
            record = original
        } else {
            record = TransactionRecord(
                amount: signedAmount,
                currencyCode: AppSettings.shared.currencyCode,
                merchant: cleanMerchant,
                date: date,
                source: .manual,
                createdAt: moment
            )
        }
        record.amount = signedAmount
        record.merchant = cleanMerchant
        record.categoryID = categoryID
        record.date = date
        record.paymentMethod = payment
        record.notes = cleanNotes
        // Saving by hand resolves any review flags.
        record.needsReview = false
        record.isPossibleDuplicate = false
        if original == nil {
            // A brand-new manual entry that matches a recent one is badged, not silently doubled.
            let duplicate = DuplicateDetector.findDuplicate(of: record, in: store.data.transactions)
            record.isPossibleDuplicate = duplicate != nil
        }

        let saved = await store.saveTransaction(record)
        isSaving = false
        guard saved else {
            return (false, nil)
        }

        var prompt: RulePrompt?
        let categoryChanged = userPickedCategory && categoryID != originalCategoryID
        if original != nil, categoryChanged, !MerchantNormalizer.isBlank(cleanMerchant), let categoryID {
            prompt = RulePrompt(
                merchant: cleanMerchant,
                categoryID: categoryID,
                categoryName: store.categoryName(for: categoryID)
            )
        }
        return (true, prompt)
    }

    func acceptRule(_ prompt: RulePrompt) async {
        await store.setRule(merchant: prompt.merchant, categoryID: prompt.categoryID)
    }
}
