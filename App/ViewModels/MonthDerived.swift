// MonthDerived.swift — everything the UI shows for one month, computed by LedgerlyCore in one go.

import Foundation
import LedgerlyCore

/// The budget snapshot, insights and chart series for one month. All numbers come from LedgerlyCore.
struct MonthDerived: Sendable {
    var month: MonthKey
    var goal: Decimal
    var snapshot: BudgetSnapshot
    var insights: [Insight]
    var slices: [CategorySlice]
    var weeklyBars: [WeeklyBar]
    var cumulative: [CumulativePoint]
    var comparisons: [CategoryComparison]
    var topMerchants: [MerchantSpend]
    var monthTransactions: [TransactionRecord]

    /// The goal that applies to `month`: its own, else the most recent earlier one, else $200.
    static func goalAmount(for month: MonthKey, goals: [MonthlyGoal]) -> Decimal {
        if let exact = goals.first(where: { $0.month == month }) {
            return exact.amount
        }
        let earlier = goals.filter { $0.month < month }.sorted { $0.month < $1.month }
        if let latest = earlier.last {
            return latest.amount
        }
        return GoalPrompt.defaultGoal
    }

    /// An empty month (the current one), used before the first load.
    static func placeholder() -> MonthDerived {
        let calendar = LedgerCalendar.current
        let start = Date()
        return compute(
            month: MonthKey(date: start, calendar: calendar),
            data: LedgerData.empty,
            now: start,
            calendar: calendar,
            currencyCode: "USD"
        )
    }

    static func compute(
        month: MonthKey,
        data: LedgerData,
        now: Date,
        calendar: LedgerCalendar,
        currencyCode: String
    ) -> MonthDerived {
        let goal = goalAmount(for: month, goals: data.goals)
        let snapshot = BudgetEngine.snapshot(
            month: month,
            now: now,
            transactions: data.transactions,
            earnings: data.earnings,
            goal: goal,
            categories: data.categories,
            calendar: calendar
        )
        let insights = InsightsEngine.insights(
            snapshot: snapshot,
            transactions: data.transactions,
            categories: data.categories,
            calendar: calendar,
            currencyCode: currencyCode
        )
        let slices = ChartData.categoryBreakdown(
            month: month,
            transactions: data.transactions,
            categories: data.categories,
            calendar: calendar
        )
        let weeklyBars = ChartData.weeklyBars(
            month: month,
            transactions: data.transactions,
            earnings: data.earnings,
            calendar: calendar
        )
        let cumulative = ChartData.cumulativeSeries(
            month: month,
            now: now,
            transactions: data.transactions,
            expectedIncome: snapshot.expectedIncome,
            goal: snapshot.goal,
            calendar: calendar
        )
        let comparisons = ChartData.monthOverMonth(
            month: month,
            transactions: data.transactions,
            categories: data.categories,
            calendar: calendar
        )
        let topMerchants = ChartData.topMerchants(
            month: month,
            transactions: data.transactions,
            calendar: calendar
        )
        let monthTransactions = BudgetEngine.transactions(
            in: month,
            from: data.transactions,
            calendar: calendar
        )
        return MonthDerived(
            month: month,
            goal: goal,
            snapshot: snapshot,
            insights: insights,
            slices: slices,
            weeklyBars: weeklyBars,
            cumulative: cumulative,
            comparisons: comparisons,
            topMerchants: topMerchants,
            monthTransactions: monthTransactions
        )
    }
}
