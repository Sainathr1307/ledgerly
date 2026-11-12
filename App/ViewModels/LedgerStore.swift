// LedgerStore.swift — the app's central view model: loads everything from the repository, reloads on
// every change, and derives the current month's numbers through LedgerlyCore.

import Foundation
import Observation
import LedgerlyCore

@MainActor
@Observable
final class LedgerStore {
    /// Everything in the store, as value types.
    private(set) var data: LedgerData = .empty
    /// False until the first load finishes.
    private(set) var hasLoaded: Bool = false
    /// The time of the last reload. All "today" logic uses this, so the UI is consistent within one render.
    private(set) var now: Date = Date()
    /// Bumped on every reload; screens with their own derived state watch it.
    private(set) var revision: Int = 0
    /// Numbers for the current month (Home).
    private(set) var current: MonthDerived = MonthDerived.placeholder()
    /// The current month's insights, reworded on device when that is available.
    private(set) var homeInsights: [Insight] = []
    /// Set when a write fails; the root view shows it in an alert.
    var errorMessage: String?

    private let repository: LedgerRepository
    @ObservationIgnored private var rephraseInput: [Insight] = []
    @ObservationIgnored private var rephraseOutput: [Insight] = []
    @ObservationIgnored private var rephraseGeneration: Int = 0

    init(repository: LedgerRepository = LedgerRepository.shared) {
        self.repository = repository
    }

    // MARK: - Loading

    /// A fresh calendar each time, so a time-zone change is picked up.
    var calendar: LedgerCalendar { LedgerCalendar.current }

    var currentMonth: MonthKey { current.month }

    func reload() async {
        let fresh = await repository.snapshotAll()
        let moment = Date()
        let calendar = LedgerCalendar.current
        data = fresh
        now = moment
        current = MonthDerived.compute(
            month: MonthKey(date: moment, calendar: calendar),
            data: fresh,
            now: moment,
            calendar: calendar,
            currencyCode: AppSettings.shared.currencyCode
        )
        revision += 1
        hasLoaded = true
        refreshHomeInsights()
    }

    /// Fire-and-forget reload, for notification and scene-phase callbacks.
    func requestReload() {
        Task {
            await self.reload()
        }
    }

    private func refreshHomeInsights() {
        let base = current.insights
        if base == rephraseInput {
            homeInsights = rephraseOutput
            return
        }
        homeInsights = base
        rephraseGeneration += 1
        let generation = rephraseGeneration
        Task {
            let reworded = await InsightRephraser.rephrase(base)
            if generation == self.rephraseGeneration {
                self.rephraseInput = base
                self.rephraseOutput = reworded
                self.homeInsights = reworded
            }
        }
    }

    // MARK: - Derived helpers

    func derived(for month: MonthKey) -> MonthDerived {
        if month == current.month {
            return current
        }
        return MonthDerived.compute(
            month: month,
            data: data,
            now: now,
            calendar: calendar,
            currencyCode: AppSettings.shared.currencyCode
        )
    }

    /// Categories the user can pick (not archived), in their order.
    var activeCategories: [CategoryRecord] {
        data.categories.filter { !$0.isArchived }
    }

    var archivedCategories: [CategoryRecord] {
        data.categories.filter { $0.isArchived }
    }

    /// The category a transaction is counted under (falls back to Other, like the engines do).
    func category(for categoryID: UUID?) -> CategoryRecord? {
        let effective = BudgetEngine.effectiveCategoryID(categoryID, categories: data.categories)
        return data.categories.first { $0.id == effective }
    }

    func categoryName(for categoryID: UUID?) -> String {
        category(for: categoryID)?.name ?? "Other"
    }

    /// Transactions waiting in the Needs Review inbox (flagged for review or as a possible duplicate), newest first.
    var reviewItems: [TransactionRecord] {
        data.transactions
            .filter { $0.needsReview || $0.isPossibleDuplicate }
            .sorted { $0.date > $1.date }
    }

    /// True when last week's earnings have not been entered. Works without notification permission.
    var isLastWeekEarningsMissing: Bool {
        EarningsReminder.isLastWeekMissing(earnings: data.earnings, now: now, calendar: calendar)
    }

    var recentTransactions: [TransactionRecord] {
        ChartData.recent(data.transactions, limit: 5)
    }

    /// Wallet cards seen so far, for the payment-method picker.
    var knownWalletCards: [PaymentMethod] {
        ChartData.paymentMethods(in: data.transactions).filter { $0.cardName != nil }
    }

    func goalAmount(for month: MonthKey) -> Decimal {
        MonthDerived.goalAmount(for: month, goals: data.goals)
    }

    /// What the goal sheet starts with: this month's goal if set, else last month's, else $200.
    func goalPrefill() -> Decimal {
        let month = MonthKey(date: Date(), calendar: calendar)
        if let exact = data.goals.first(where: { $0.month == month }) {
            return exact.amount
        }
        let earlier = data.goals.filter { $0.month < month }.sorted { $0.month < $1.month }
        return GoalPrompt.prefillAmount(previousGoal: earlier.last?.amount)
    }

    func knownMerchants() async -> [String] {
        await repository.knownMerchants()
    }

    // MARK: - Writes (each one reloads afterwards; the change notification reloads again, harmlessly)

    @discardableResult
    func saveTransaction(_ record: TransactionRecord) async -> Bool {
        do {
            try await repository.upsert(record)
            await reload()
            return true
        } catch {
            report(error, doing: "save the transaction")
            return false
        }
    }

    func deleteTransaction(id: UUID) async {
        do {
            try await repository.deleteTransaction(id: id)
            await reload()
        } catch {
            report(error, doing: "delete the transaction")
        }
    }

    func setRule(merchant: String, categoryID: UUID) async {
        do {
            try await repository.setRule(merchant: merchant, categoryID: categoryID)
            await reload()
        } catch {
            report(error, doing: "save the rule")
        }
    }

    func deleteRule(normalizedMerchant: String) async {
        do {
            try await repository.deleteRule(normalizedMerchant: normalizedMerchant)
            await reload()
        } catch {
            report(error, doing: "delete the rule")
        }
    }

    func saveCategory(_ category: CategoryRecord) async {
        do {
            try await repository.upsert(category)
            await reload()
        } catch {
            report(error, doing: "save the category")
        }
    }

    func reorderCategories(_ orderedIDs: [UUID]) async {
        do {
            try await repository.reorderCategories(orderedIDs)
            await reload()
        } catch {
            report(error, doing: "reorder the categories")
        }
    }

    func setEarning(weekStart: Date, amount: Decimal) async {
        do {
            try await repository.setEarning(weekStart: weekStart, amount: amount)
        } catch {
            report(error, doing: "save the earnings")
        }
    }

    func deleteEarning(weekStart: Date) async {
        do {
            try await repository.deleteEarning(weekStart: weekStart)
        } catch {
            report(error, doing: "remove the earnings")
        }
    }

    func setGoal(_ amount: Decimal, for month: MonthKey) async {
        do {
            try await repository.setGoal(amount, for: month)
            await reload()
        } catch {
            report(error, doing: "save the goal")
        }
    }

    /// Makes sure the current month has a stored goal (the pre-filled default), so there is always one.
    func ensureCurrentGoal() async {
        let month = MonthKey(date: Date(), calendar: calendar)
        let existing = await repository.goal(for: month)
        if existing == nil {
            let previous = await repository.latestGoal(before: month)
            let amount = GoalPrompt.prefillAmount(previousGoal: previous?.amount)
            await setGoal(amount, for: month)
        }
    }

    func seedDefaultCategories() async {
        do {
            try await repository.seedDefaultCategoriesIfNeeded()
        } catch {
            report(error, doing: "set up the categories")
        }
    }

    func eraseAll() async {
        do {
            try await repository.eraseAll()
            await reload()
        } catch {
            report(error, doing: "erase the data")
        }
    }

    /// Inserts one zero-amount, blank-merchant Wallet transaction (UI tests: `-uiTestingSeedReview`).
    func seedReviewItemForUITests() async {
        let moment = Date()
        let categorizer = Categorizer(rules: data.rules, categories: DefaultCategories.all)
        let ingestor = TransactionIngestor(
            categorizer: categorizer,
            defaultCurrencyCode: AppSettings.shared.currencyCode
        )
        let incoming = IncomingTransaction(rawAmount: "0", merchant: nil, cardName: "Test Card", date: moment)
        let result = ingestor.ingest(incoming, existing: [], now: moment)
        await saveTransaction(result.record)
    }

    private func report(_ error: Error, doing action: String) {
        errorMessage = "Couldn't \(action). \(error.localizedDescription)"
    }
}
