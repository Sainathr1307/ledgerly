// InsightsViewModel.swift — the Insights tab: which month is selected and that month's numbers from LedgerlyCore.

import Foundation
import Observation
import LedgerlyCore

@MainActor
@Observable
final class InsightsViewModel {
    /// The month being browsed. Starts on the current month; can't go past it.
    var selectedMonth: MonthKey = MonthDerived.placeholder().month
    /// Numbers for `selectedMonth`.
    private(set) var derived: MonthDerived = MonthDerived.placeholder()
    /// Insight cards for `selectedMonth` (reworded on device when that is available).
    private(set) var insights: [Insight] = []

    init() {}

    func canGoForward(store: LedgerStore) -> Bool {
        selectedMonth < store.currentMonth
    }

    func goBack() {
        selectedMonth = selectedMonth.previous
    }

    func goForward(store: LedgerStore) {
        if canGoForward(store: store) {
            selectedMonth = selectedMonth.next
        }
    }

    func goToCurrentMonth(store: LedgerStore) {
        selectedMonth = store.currentMonth
    }

    /// Recomputes for the selected month, shows the engine's insights right away, then swaps in the reworded ones.
    func refresh(store: LedgerStore) async {
        let month = selectedMonth
        let fresh = store.derived(for: month)
        derived = fresh
        insights = fresh.insights
        let reworded = await InsightRephraser.rephrase(fresh.insights)
        if Task.isCancelled || month != selectedMonth {
            return
        }
        insights = reworded
    }
}
