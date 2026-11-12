// LogWalletTransactionIntent.swift — the "Log Wallet Transaction" action that the Shortcuts Wallet automation runs in the background.

import AppIntents
import Foundation

/// Runs without opening the app. The Shortcuts "Transaction" (Wallet) automation passes in the
/// amount, merchant and card of a tap-to-pay purchase.
///
/// All three parameters are optional text on purpose:
/// - Shortcuts turns whatever is plugged in (a number, a currency amount, plain text) into text,
///   so "$12.40", "12,40" and 12.4 all arrive here as strings and are parsed by Core's `AmountParser`.
/// - iOS sometimes sends no amount or no merchant. A required parameter would make Shortcuts stop
///   and ask for a value, which fails in a background automation. Optional parameters let the
///   transaction be saved anyway and sent to Needs Review.
struct LogWalletTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Wallet Transaction"

    static let description = IntentDescription(
        "Saves a Wallet purchase in Ledgerly, picks a category for it and posts a confirmation. Use it in a Shortcuts Transaction automation and pass in the Amount, Merchant and Card from the Shortcut Input."
    )

    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "Amount",
        description: "The amount paid, as text or a number, for example $12.40. Currency symbols and commas are fine."
    )
    var amount: String?

    @Parameter(
        title: "Merchant",
        description: "Where the purchase was made."
    )
    var merchant: String?

    @Parameter(
        title: "Card",
        description: "The name of the Wallet card that was used."
    )
    var cardName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant) on \(\.$cardName)")
    }

    init() {}

    /// Never throws for bad input (that goes to Needs Review). Only a failed save throws, so
    /// Shortcuts reports the automation as failed instead of pretending it worked.
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await WalletTransactionLogger.log(
            amount: amount ?? "",
            merchant: merchant,
            cardName: cardName
        )
        let message = result.notificationBody
        return .result(dialog: "\(message)")
    }
}
