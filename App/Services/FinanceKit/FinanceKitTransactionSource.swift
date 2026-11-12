// FinanceKitTransactionSource.swift — optional Apple Card / Apple Cash / Savings source; compiled only with the FINANCEKIT_ENABLED flag.

import Foundation
import LedgerlyCore

/// Lets the rest of the app ask whether the FinanceKit code is in this build without mentioning FinanceKit.
enum FinanceKitSupport {
    #if FINANCEKIT_ENABLED && canImport(FinanceKit)
    static let isCompiledIn = true
    #else
    static let isCompiledIn = false
    #endif
}

#if FINANCEKIT_ENABLED && canImport(FinanceKit)
import FinanceKit

// NOTE: nothing in this block is part of the default build, and it has never been compiled:
// FinanceKit needs the com.apple.developer.financekit entitlement, which Apple only grants to
// organisations. See "FinanceKit" in the README before turning the flag on.

enum FinanceKitSyncError: LocalizedError {
    case notAvailable
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Apple Card, Apple Cash and Savings data isn't available on this iPhone."
        case .notAuthorized:
            return "Ledgerly doesn't have permission to read your Apple Card, Apple Cash and Savings transactions. You can allow it in the Settings app under Privacy & Security."
        }
    }
}

/// A FinanceKit transaction mapped to Core's incoming shape, keeping FinanceKit's own id so the
/// same transaction is never imported twice.
struct FinanceKitFetchedTransaction: Sendable {
    let id: UUID
    let incoming: IncomingTransaction
}

struct FinanceKitTransactionSource: TransactionSource {
    var kind: SourceKind { .financeKit }

    func isAvailable() async -> Bool {
        FinanceStore.isDataAvailable(.financialData)
    }

    /// Shows the system permission sheet the first time; afterwards just reports the answer.
    func requestAuthorization() async -> Bool {
        do {
            let status = try await FinanceStore.shared.requestAuthorization()
            return status == .authorized
        } catch {
            return false
        }
    }

    func fetch(since: Date?) async throws -> [IncomingTransaction] {
        let fetched = try await fetchWithIDs(since: since)
        return fetched.map { $0.incoming }
    }

    /// Money leaving an account (a purchase) becomes a positive amount. Money coming back is only
    /// kept when FinanceKit calls it a refund, and becomes a negative amount. Card payments,
    /// deposits, transfers in and interest are not spending and are left out.
    func fetchWithIDs(since: Date?) async throws -> [FinanceKitFetchedTransaction] {
        guard FinanceStore.isDataAvailable(.financialData) else { throw FinanceKitSyncError.notAvailable }
        let store = FinanceStore.shared

        var accountNames: [UUID: String] = [:]
        let accounts = try await store.accounts(query: AccountQuery())
        for account in accounts {
            accountNames[account.id] = account.displayName
        }

        let query: TransactionQuery
        if let since {
            query = TransactionQuery(
                sortDescriptors: [SortDescriptor(\FinanceKit.Transaction.transactionDate)],
                predicate: #Predicate<FinanceKit.Transaction> { $0.transactionDate >= since }
            )
        } else {
            query = TransactionQuery(
                sortDescriptors: [SortDescriptor(\FinanceKit.Transaction.transactionDate)]
            )
        }
        let transactions = try await store.transactions(query: query)

        var result: [FinanceKitFetchedTransaction] = []
        for transaction in transactions {
            let isCredit = transaction.creditDebitIndicator == .credit
            if isCredit && transaction.transactionType != .refund { continue }

            let merchant = transaction.merchantName ?? transaction.transactionDescription
            let incoming = IncomingTransaction(
                // Plain "12.40" text, parsed with a fixed locale by FinanceKitSync.
                rawAmount: MoneyFormat.plain(transaction.transactionAmount.amount),
                merchant: merchant,
                cardName: accountNames[transaction.accountID],
                date: transaction.transactionDate,
                source: .financeKit,
                currencyCode: transaction.transactionAmount.currencyCode,
                negateAmount: isCredit
            )
            result.append(FinanceKitFetchedTransaction(id: transaction.id, incoming: incoming))
        }
        return result
    }
}

enum FinanceKitSync {
    private static let lastSyncKey = "financeKitLastSyncDate"

    /// Pulls new Apple Card / Cash / Savings transactions into the ledger and returns how many were added.
    ///
    /// - A transaction that was already imported (same FinanceKit id) is skipped, so edits you made to it survive.
    /// - A transaction that looks like one logged another way (for example by the Wallet automation
    ///   seconds earlier) is still saved, flagged as a possible duplicate, never dropped.
    static func syncNow() async throws -> Int {
        let source = FinanceKitTransactionSource()
        guard await source.isAvailable() else { throw FinanceKitSyncError.notAvailable }
        guard await source.requestAuthorization() else { throw FinanceKitSyncError.notAuthorized }

        let now = Date()
        let defaults = UserDefaults.standard
        let since: Date
        if let last = defaults.object(forKey: lastSyncKey) as? Date {
            // Go back a week past the last sync: transactions can show up late.
            since = last.addingTimeInterval(-7 * 24 * 60 * 60)
        } else {
            // First sync: about three months, the same span the charts look at.
            since = now.addingTimeInterval(-92 * 24 * 60 * 60)
        }
        let fetched = try await source.fetchWithIDs(since: since)

        let repository = LedgerRepository.shared
        try? await repository.seedDefaultCategoriesIfNeeded()
        let data = await repository.snapshotAll()
        let categories = data.categories.isEmpty ? DefaultCategories.all : data.categories
        let ingestor = TransactionIngestor(
            categorizer: Categorizer(rules: data.rules, categories: categories),
            locale: Locale(identifier: "en_US_POSIX"),
            defaultCurrencyCode: AppSettings.storedCurrencyCode
        )

        var known = data.transactions
        var knownIDs = Set(known.map { $0.id })
        var newRecords: [TransactionRecord] = []
        for item in fetched {
            if knownIDs.contains(item.id) { continue }
            let record = ingestor.ingest(item.incoming, existing: known, now: now, id: item.id).record
            newRecords.append(record)
            known.append(record)
            knownIDs.insert(record.id)
        }

        try await repository.upsertTransactions(newRecords)
        defaults.set(now, forKey: lastSyncKey)
        return newRecords.count
    }
}
#endif
