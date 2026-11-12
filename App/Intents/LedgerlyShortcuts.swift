// LedgerlyShortcuts.swift — makes "Log Wallet Transaction" show up in the Shortcuts app and Spotlight without any setup.

import AppIntents

struct LedgerlyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWalletTransactionIntent(),
            phrases: [
                "Log a Wallet transaction in \(.applicationName)",
                "Log a purchase in \(.applicationName)",
                "Add a transaction to \(.applicationName)"
            ],
            shortTitle: "Log Wallet Transaction",
            systemImageName: "creditcard"
        )
    }
}
