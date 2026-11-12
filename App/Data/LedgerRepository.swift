// LedgerRepository.swift — the only door to the SwiftData store; hands out LedgerlyCore value types.

import Foundation
import SwiftData
import LedgerlyCore

extension Notification.Name {
    /// Posted on the main thread after every successful repository write, including writes made
    /// by the background App Intent. View models reload when they see it.
    static let ledgerDidChange = Notification.Name("LedgerlyLedgerDidChange")
}

/// Everything in the store, read in one go.
struct LedgerData: Sendable, Equatable {
    /// Newest first.
    var transactions: [TransactionRecord] = []
    /// Sorted by `sortOrder`; includes archived categories.
    var categories: [CategoryRecord] = []
    var rules: [MerchantRule] = []
    /// Oldest week first.
    var earnings: [WeeklyEarning] = []
    /// Oldest month first.
    var goals: [MonthlyGoal] = []

    static let empty = LedgerData()
}

@ModelActor
actor LedgerRepository {
    /// The repository over `SharedModelContainer.shared`. The app and the App Intent both use this one.
    static let shared = LedgerRepository(modelContainer: SharedModelContainer.shared)

    // MARK: - Transactions

    /// All transactions, newest first.
    func allTransactions() -> [TransactionRecord] {
        fetchTransactionEntities().map { $0.record }
    }

    /// Transactions with `interval.start <= date < interval.end` (end is exclusive), newest first.
    /// Pass nil for everything.
    func transactions(in interval: DateInterval?) -> [TransactionRecord] {
        guard let interval else { return allTransactions() }
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<TransactionEntity>(
            predicate: #Predicate<TransactionEntity> { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\TransactionEntity.date, order: .reverse)]
        )
        let entities = (try? modelContext.fetch(descriptor)) ?? []
        return entities.map { $0.record }
    }

    /// One transaction by id, or nil.
    func transaction(id: UUID) -> TransactionRecord? {
        fetchTransactionEntity(id: id)?.record
    }

    /// Inserts the transaction, or updates it in place when one with the same id exists.
    func upsert(_ record: TransactionRecord) throws {
        applyUpsert(record)
        try saveAndNotify()
    }

    /// Inserts or updates many transactions with a single save and a single change notification.
    func upsertTransactions(_ records: [TransactionRecord]) throws {
        guard !records.isEmpty else { return }
        for record in records {
            applyUpsert(record)
        }
        try saveAndNotify()
    }

    /// Deletes the transaction with this id. Does nothing when it doesn't exist.
    func deleteTransaction(id: UUID) throws {
        guard let entity = fetchTransactionEntity(id: id) else { return }
        modelContext.delete(entity)
        try saveAndNotify()
    }

    /// Distinct merchant names the user has used, most frequent first, then most recent.
    /// Spellings that normalize to the same merchant are merged; the most recent spelling is shown.
    func knownMerchants() -> [String] {
        struct Tally {
            var displayName: String
            var count: Int
            var latest: Date
        }
        var tallies: [String: Tally] = [:]
        for entity in fetchTransactionEntities() {
            let name = entity.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            var key = MerchantNormalizer.normalize(name)
            if key.isEmpty { key = name.uppercased() }
            if var tally = tallies[key] {
                tally.count += 1
                if entity.date > tally.latest {
                    tally.latest = entity.date
                    tally.displayName = name
                }
                tallies[key] = tally
            } else {
                tallies[key] = Tally(displayName: name, count: 1, latest: entity.date)
            }
        }
        let sorted = tallies.values.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            if lhs.latest != rhs.latest { return lhs.latest > rhs.latest }
            return lhs.displayName < rhs.displayName
        }
        return sorted.map { $0.displayName }
    }

    // MARK: - Categories

    /// Categories sorted by `sortOrder`. Archived ones are left out unless asked for.
    func categories(includeArchived: Bool) -> [CategoryRecord] {
        let records = fetchCategoryEntities().map { $0.record }
        if includeArchived { return records }
        return records.filter { !$0.isArchived }
    }

    /// Inserts the category, or updates it in place when one with the same id exists.
    func upsert(_ record: CategoryRecord) throws {
        applyUpsert(record)
        try saveAndNotify()
    }

    /// Rewrites `sortOrder` so the given ids come first in the given order. Categories not in
    /// the list keep their relative order and go after the listed ones.
    func reorderCategories(_ orderedIDs: [UUID]) throws {
        let entities = fetchCategoryEntities()
        var position: [UUID: Int] = [:]
        for id in orderedIDs where position[id] == nil {
            position[id] = position.count
        }
        var next = position.count
        for entity in entities {
            if let index = position[entity.id] {
                entity.sortOrder = index
            } else {
                entity.sortOrder = next
                next += 1
            }
        }
        try saveAndNotify()
    }

    /// Inserts the ten default categories, but only when the store has no categories at all.
    func seedDefaultCategoriesIfNeeded() throws {
        let existing = (try? modelContext.fetchCount(FetchDescriptor<CategoryEntity>())) ?? 0
        guard existing == 0 else { return }
        for record in DefaultCategories.all {
            modelContext.insert(CategoryEntity(record: record))
        }
        try saveAndNotify()
    }

    // MARK: - Merchant rules

    /// Learned merchant → category rules, sorted by merchant.
    func rules() -> [MerchantRule] {
        fetchRuleEntities().map { $0.record }
    }

    /// Saves "always categorize this merchant as this category". The merchant is normalized here,
    /// so pass the raw merchant text. Does nothing when the merchant normalizes to an empty string.
    func setRule(merchant: String, categoryID: UUID) throws {
        let normalized = MerchantNormalizer.normalize(merchant)
        guard !normalized.isEmpty else { return }
        applyRule(MerchantRule(normalizedMerchant: normalized, categoryID: categoryID))
        try saveAndNotify()
    }

    /// Deletes the rule with this already-normalized merchant key (use `MerchantRule.normalizedMerchant`).
    func deleteRule(normalizedMerchant: String) throws {
        guard let entity = fetchRuleEntity(normalizedMerchant: normalizedMerchant) else { return }
        modelContext.delete(entity)
        try saveAndNotify()
    }

    // MARK: - Weekly earnings

    /// All weekly earnings, oldest week first.
    func earnings() -> [WeeklyEarning] {
        fetchEarningEntities().map { $0.record }
    }

    /// Sets the amount earned in the week that contains `weekStart`. Any date in the week works;
    /// it is snapped to that week's Monday 00:00 in the current time zone.
    func setEarning(weekStart: Date, amount: Decimal) throws {
        let monday = LedgerRepository.monday(for: weekStart)
        applyEarning(WeeklyEarning(weekStart: monday, amount: amount))
        try saveAndNotify()
    }

    /// Deletes the earning for the week that contains `weekStart`. Does nothing when there is none.
    func deleteEarning(weekStart: Date) throws {
        let monday = LedgerRepository.monday(for: weekStart)
        guard let entity = fetchEarningEntity(weekStart: monday) else { return }
        modelContext.delete(entity)
        try saveAndNotify()
    }

    // MARK: - Monthly goals

    /// The goal saved for exactly this month, or nil.
    func goal(for month: MonthKey) -> MonthlyGoal? {
        fetchGoalEntity(year: month.year, month: month.month)?.record
    }

    /// The most recent goal saved for a month strictly before this one, or nil.
    func latestGoal(before month: MonthKey) -> MonthlyGoal? {
        let limit = month.year * 12 + month.month
        var best: MonthlyGoalEntity?
        for entity in fetchGoalEntities() {
            let index = entity.year * 12 + entity.month
            if index >= limit { continue }
            if let current = best {
                if index > current.year * 12 + current.month { best = entity }
            } else {
                best = entity
            }
        }
        return best?.record
    }

    /// Sets (or replaces) the savings goal for a month.
    func setGoal(_ amount: Decimal, for month: MonthKey) throws {
        applyGoal(MonthlyGoal(month: month, amount: amount))
        try saveAndNotify()
    }

    // MARK: - Bulk

    /// Everything in the store in one call. View models use this to reload.
    func snapshotAll() -> LedgerData {
        LedgerData(
            transactions: fetchTransactionEntities().map { $0.record },
            categories: fetchCategoryEntities().map { $0.record },
            rules: fetchRuleEntities().map { $0.record },
            earnings: fetchEarningEntities().map { $0.record },
            goals: fetchGoalEntities().map { $0.record }
        )
    }

    /// Inserts or updates everything in `data` with a single save and a single change notification.
    /// Existing rows that are not mentioned in `data` are left alone. Used by the demo seeder and imports.
    /// Rule merchants and earning week starts are stored exactly as given (not re-normalized).
    func importData(_ data: LedgerData) throws {
        for record in data.categories { applyUpsert(record) }
        for record in data.transactions { applyUpsert(record) }
        for record in data.rules { applyRule(record) }
        for record in data.earnings { applyEarning(record) }
        for record in data.goals { applyGoal(record) }
        try saveAndNotify()
    }

    /// Deletes every row of every entity type, then puts the default categories back.
    func eraseAll() throws {
        for entity in fetchTransactionEntities() { modelContext.delete(entity) }
        for entity in fetchCategoryEntities() { modelContext.delete(entity) }
        for entity in fetchRuleEntities() { modelContext.delete(entity) }
        for entity in fetchEarningEntities() { modelContext.delete(entity) }
        for entity in fetchGoalEntities() { modelContext.delete(entity) }
        // Save the deletes first so re-inserting the defaults (same fixed ids) can't collide with them.
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        for record in DefaultCategories.all {
            modelContext.insert(CategoryEntity(record: record))
        }
        try saveAndNotify()
    }

    // MARK: - Private: save

    private func saveAndNotify() throws {
        do {
            try modelContext.save()
        } catch {
            // Drop the half-applied changes so a failed write can't leak into the next one.
            modelContext.rollback()
            throw error
        }
        Task { @MainActor in
            NotificationCenter.default.post(name: .ledgerDidChange, object: nil)
        }
    }

    private static func monday(for date: Date) -> Date {
        LedgerCalendar(timeZone: TimeZone.current).weekStart(for: date)
    }

    // MARK: - Private: in-place upserts (no save)

    private func applyUpsert(_ record: TransactionRecord) {
        if let existing = fetchTransactionEntity(id: record.id) {
            existing.apply(record)
        } else {
            modelContext.insert(TransactionEntity(record: record))
        }
    }

    private func applyUpsert(_ record: CategoryRecord) {
        if let existing = fetchCategoryEntity(id: record.id) {
            existing.apply(record)
        } else {
            modelContext.insert(CategoryEntity(record: record))
        }
    }

    private func applyRule(_ record: MerchantRule) {
        if let existing = fetchRuleEntity(normalizedMerchant: record.normalizedMerchant) {
            existing.apply(record)
        } else {
            modelContext.insert(MerchantRuleEntity(record: record))
        }
    }

    private func applyEarning(_ record: WeeklyEarning) {
        if let existing = fetchEarningEntity(weekStart: record.weekStart) {
            existing.apply(record)
        } else {
            modelContext.insert(WeeklyEarningEntity(record: record))
        }
    }

    private func applyGoal(_ record: MonthlyGoal) {
        if let existing = fetchGoalEntity(year: record.month.year, month: record.month.month) {
            existing.apply(record)
        } else {
            modelContext.insert(MonthlyGoalEntity(record: record))
        }
    }

    // MARK: - Private: fetches
    // Predicates are kept to plain equality / range checks on stored properties, with every
    // compared value captured in a local constant first. Anything fancier is filtered in Swift.

    private func fetchTransactionEntities() -> [TransactionEntity] {
        let descriptor = FetchDescriptor<TransactionEntity>(
            sortBy: [SortDescriptor(\TransactionEntity.date, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchTransactionEntity(id: UUID) -> TransactionEntity? {
        var descriptor = FetchDescriptor<TransactionEntity>(
            predicate: #Predicate<TransactionEntity> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchCategoryEntities() -> [CategoryEntity] {
        let descriptor = FetchDescriptor<CategoryEntity>(
            sortBy: [SortDescriptor(\CategoryEntity.sortOrder), SortDescriptor(\CategoryEntity.name)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchCategoryEntity(id: UUID) -> CategoryEntity? {
        var descriptor = FetchDescriptor<CategoryEntity>(
            predicate: #Predicate<CategoryEntity> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchRuleEntities() -> [MerchantRuleEntity] {
        let descriptor = FetchDescriptor<MerchantRuleEntity>(
            sortBy: [SortDescriptor(\MerchantRuleEntity.normalizedMerchant)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchRuleEntity(normalizedMerchant: String) -> MerchantRuleEntity? {
        var descriptor = FetchDescriptor<MerchantRuleEntity>(
            predicate: #Predicate<MerchantRuleEntity> { $0.normalizedMerchant == normalizedMerchant }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchEarningEntities() -> [WeeklyEarningEntity] {
        let descriptor = FetchDescriptor<WeeklyEarningEntity>(
            sortBy: [SortDescriptor(\WeeklyEarningEntity.weekStart)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchEarningEntity(weekStart: Date) -> WeeklyEarningEntity? {
        var descriptor = FetchDescriptor<WeeklyEarningEntity>(
            predicate: #Predicate<WeeklyEarningEntity> { $0.weekStart == weekStart }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchGoalEntities() -> [MonthlyGoalEntity] {
        let descriptor = FetchDescriptor<MonthlyGoalEntity>(
            sortBy: [SortDescriptor(\MonthlyGoalEntity.key)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchGoalEntity(year: Int, month: Int) -> MonthlyGoalEntity? {
        let key = MonthlyGoalEntity.makeKey(year: year, month: month)
        var descriptor = FetchDescriptor<MonthlyGoalEntity>(
            predicate: #Predicate<MonthlyGoalEntity> { $0.key == key }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }
}
