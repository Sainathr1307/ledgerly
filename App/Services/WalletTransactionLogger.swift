// WalletTransactionLogger.swift — the one code path that saves a Wallet tap: used by the App Intent and by the "Test it" button.

import Foundation
import LedgerlyCore

/// What `WalletTransactionLogger.log` saved, plus the text it used for the notification.
struct WalletLogResult: Sendable {
    /// The record exactly as it was saved (check `needsReview` / `isPossibleDuplicate`).
    let record: TransactionRecord
    /// Name of the category the transaction was filed under.
    let categoryName: String
    let notificationTitle: String
    /// e.g. "Logged $12.40 at Starbucks · Food & Dining", or Core's review wording.
    let notificationBody: String
}

enum WalletTransactionLogger {
    /// How far either side of the purchase time to look for an existing copy. Core's duplicate
    /// window is 3 minutes; this only has to be at least that wide.
    private static let duplicateLookupSeconds: TimeInterval = 600

    /// Saves one Wallet transaction.
    ///
    /// Bad input never throws and is never dropped: an amount of 0, an amount that can't be read,
    /// or a blank merchant is saved with `needsReview = true`; a repeat of something logged in the
    /// last three minutes is saved and flagged as a possible duplicate. The only thing that throws
    /// is the store failing to save.
    ///
    /// - Parameters:
    ///   - amount: the amount as text, however Shortcuts sent it ("$12.40", "12,40", "12.4", "").
    ///   - merchant: merchant name, may be nil or blank.
    ///   - cardName: Wallet card name, may be nil or blank.
    ///   - date: when the purchase happened (defaults to now).
    static func log(
        amount: String,
        merchant: String?,
        cardName: String?,
        date: Date = Date()
    ) async throws -> WalletLogResult {
        let repository = LedgerRepository.shared

        // The automation can fire before the app has ever been opened, so make sure the default
        // categories exist. If seeding fails we still log, using the built-in list to categorize.
        try? await repository.seedDefaultCategoriesIfNeeded()

        let storedCategories = await repository.categories(includeArchived: true)
        let categories = storedCategories.isEmpty ? DefaultCategories.all : storedCategories
        let rules = await repository.rules()
        let nearby = await repository.transactions(
            in: DateInterval(
                start: date.addingTimeInterval(-duplicateLookupSeconds),
                end: date.addingTimeInterval(duplicateLookupSeconds)
            )
        )

        let ingestor = TransactionIngestor(
            categorizer: Categorizer(rules: rules, categories: categories),
            defaultCurrencyCode: AppSettings.storedCurrencyCode
        )
        let incoming = IncomingTransaction(
            rawAmount: amount,
            merchant: merchant,
            cardName: cardName,
            date: date,
            source: .walletShortcut
        )
        let result = ingestor.ingest(incoming, existing: nearby, now: Date())
        let record = result.record

        // Saving posts .ledgerDidChange, so any open screen refreshes straight away.
        try await repository.upsert(record)

        let categoryName = categories.first(where: { $0.id == record.categoryID })?.name ?? "Other"
        let title = TransactionIngestor.notificationTitle(for: record)
        let body = TransactionIngestor.notificationText(for: record, categoryName: categoryName)

        if !LaunchFlags.isUITesting {
            // Returns false (and does nothing) when notifications are turned off; that's fine.
            await NotificationService.postTransactionLogged(
                title: title,
                body: body,
                needsReview: record.needsReview
            )
        }

        return WalletLogResult(
            record: record,
            categoryName: categoryName,
            notificationTitle: title,
            notificationBody: body
        )
    }
}
