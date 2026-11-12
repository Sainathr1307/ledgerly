// HomeView.swift — the dashboard: earnings card, Needs Review, goal progress, donut, top insights, recent transactions.

import SwiftUI
import LedgerlyCore

struct HomeView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(SheetCoordinator.self) private var sheets
    @State private var editing: TransactionRecord?

    private var router: AppRouter { AppRouter.shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    alerts
                    GoalProgressCard(
                        snapshot: store.current.snapshot,
                        onEditGoal: { sheets.active = .goalEdit },
                        onAddEarnings: { sheets.active = .earnings }
                    )
                    if store.data.transactions.isEmpty {
                        firstRunCard
                    } else {
                        donutCard
                        insightsCard
                        recentCard
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(DateText.monthTitle(store.currentMonth, calendar: store.calendar))
        }
        .sheet(item: $editing) { record in
            TransactionEditorSheet(store: store, editing: record)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var alerts: some View {
        if store.isLastWeekEarningsMissing {
            EarningsNeededCard(weekText: lastWeekText) {
                sheets.active = .earnings
            }
        }
        if !store.reviewItems.isEmpty {
            NeedsReviewBanner(count: store.reviewItems.count) {
                sheets.active = .review
            }
        }
    }

    private var lastWeekText: String {
        let calendar = store.calendar
        let weekStart = EarningsReminder.lastWeekStart(now: store.now, calendar: calendar)
        return DateText.weekRange(weekStart: weekStart, calendar: calendar)
    }

    private var firstRunCard: some View {
        CardView {
            EmptyStateView(
                title: "No spending yet",
                systemImage: "cart",
                message: "Add a purchase with the + button, or set up the Wallet automation in Settings so card payments log themselves.",
                actionTitle: "Add a transaction",
                action: { router.isAddSheetPresented = true }
            )
        }
    }

    private var donutCard: some View {
        CardView(title: "Spending by category") {
            let slices = store.current.slices
            if slices.isEmpty {
                EmptyStateView(
                    title: "Nothing spent this month",
                    systemImage: "chart.pie",
                    message: "Your categories will show up here after the first purchase of the month."
                )
            } else {
                CategoryDonutChart(slices: slices, totalText: Money.string(store.current.snapshot.spent))
                ForEach(Array(slices.prefix(4))) { slice in
                    CategoryLegendRow(slice: slice)
                }
                Button("See all charts") {
                    router.selectedTab = .insights
                }
                .font(.footnote)
                .accessibilityIdentifier("seeAllChartsButton")
            }
        }
    }

    private var insightsCard: some View {
        CardView(title: "Insights") {
            let top = InsightsEngine.top(store.homeInsights, count: 3)
            if top.isEmpty {
                Text("Insights appear once there is a little more data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(top) { insight in
                    InsightCard(insight: insight)
                }
            }
        }
    }

    private var recentCard: some View {
        CardView(title: "Recent transactions") {
            let recent = store.recentTransactions
            ForEach(Array(recent.enumerated()), id: \.element.id) { index, record in
                Button {
                    editing = record
                } label: {
                    TransactionRow(
                        record: record,
                        category: store.category(for: record.categoryID),
                        showsDate: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the transaction for editing")
                .accessibilityIdentifier("recent_row_\(index)")
                if index < recent.count - 1 {
                    Divider()
                }
            }
            Button("See all transactions") {
                router.selectedTab = .transactions
            }
            .font(.footnote)
            .accessibilityIdentifier("seeAllTransactionsButton")
        }
    }
}
