// DemoDataSeeder.swift — loads three months of sample data in DEBUG builds only; does nothing in release builds.

import Foundation
import LedgerlyCore

enum DemoDataSeeder {
    /// Loads the demo set once, on a fresh install of a DEBUG build.
    /// Does nothing under UI tests, when it has already been loaded, or when the store already has transactions.
    static func seedIfNeeded() async {
        #if DEBUG
        if LaunchFlags.isUITesting { return }
        let alreadyLoaded = await MainActor.run { AppSettings.shared.demoDataLoaded }
        if alreadyLoaded { return }
        let existing = await LedgerRepository.shared.allTransactions()
        if !existing.isEmpty { return }
        await load(erasingFirst: false)
        #endif
    }

    /// Erases everything and loads the demo set again, no questions asked.
    /// Used by the DEBUG row in Settings and by the `-uiTestingDemoData` launch flag.
    static func reload() async {
        #if DEBUG
        await load(erasingFirst: true)
        #endif
    }

    #if DEBUG
    private static func load(erasingFirst: Bool) async {
        let repository = LedgerRepository.shared
        let demo = DemoData.generate(now: Date(), calendar: LedgerCalendar.current)
        let data = LedgerData(
            transactions: demo.transactions,
            categories: demo.categories,
            earnings: demo.earnings,
            goals: demo.goals
        )
        do {
            if erasingFirst {
                try await repository.eraseAll()
            }
            // One save and one change notification for the whole set.
            try await repository.importData(data)
            await MainActor.run { AppSettings.shared.demoDataLoaded = true }
        } catch {
            // Demo data is a convenience for checking screens. If it can't be saved, start empty.
            print("Ledgerly demo data could not be loaded: \(error)")
        }
    }
    #endif
}
