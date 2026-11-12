// InsightsView.swift — the Insights tab: month picker, every chart, top merchants, and all insight cards.

import SwiftUI
import LedgerlyCore

/// Identifies what the Insights screen must recompute for.
private struct InsightsRefreshKey: Equatable {
    let month: MonthKey
    let revision: Int
}

/// A category to drill into (chart tap).
struct CategoryDrill: Hashable {
    let categoryID: UUID
    let month: MonthKey
}

struct InsightsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var model = InsightsViewModel()
    @State private var selectedAngle: Double?
    @State private var drill: CategoryDrill?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MonthPickerBar(
                        title: DateText.monthTitle(model.selectedMonth, calendar: store.calendar),
                        canGoForward: model.canGoForward(store: store),
                        onBack: { model.goBack() },
                        onForward: { model.goForward(store: store) }
                    )
                    donutCard
                    WeeklyBarsCard(bars: model.derived.weeklyBars, calendar: store.calendar)
                    CumulativeCard(points: model.derived.cumulative)
                    MonthOverMonthCard(
                        comparisons: model.derived.comparisons,
                        currentLabel: DateText.monthShort(model.selectedMonth, calendar: store.calendar),
                        previousLabel: DateText.monthShort(model.selectedMonth.previous, calendar: store.calendar)
                    )
                    TopMerchantsCard(merchants: model.derived.topMerchants)
                    insightCards
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Insights")
            .navigationDestination(item: $drill) { target in
                CategoryTransactionsView(categoryID: target.categoryID, month: target.month)
            }
        }
        .task(id: InsightsRefreshKey(month: model.selectedMonth, revision: store.revision)) {
            await model.refresh(store: store)
        }
        .onChange(of: selectedAngle) { _, newValue in
            openCategory(at: newValue)
        }
    }

    private var donutCard: some View {
        CardView(title: "Spending by category") {
            let slices = model.derived.slices
            if slices.isEmpty {
                EmptyStateView(
                    title: "No spending this month",
                    systemImage: "chart.pie",
                    message: "There is nothing to chart for this month."
                )
            } else {
                CategoryDonutChart(
                    slices: slices,
                    totalText: Money.string(model.derived.snapshot.spent),
                    angleSelection: $selectedAngle
                )
                Text("Tap a category to see its transactions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(slices) { slice in
                    NavigationLink {
                        CategoryTransactionsView(categoryID: slice.categoryID, month: model.selectedMonth)
                    } label: {
                        CategoryLegendRow(slice: slice)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows this category's transactions")
                    .accessibilityIdentifier("legend_" + slice.name)
                }
            }
        }
    }

    private var insightCards: some View {
        CardView(title: "Insights") {
            if model.insights.isEmpty {
                EmptyStateView(
                    title: "No insights for this month",
                    systemImage: "lightbulb",
                    message: "Insights appear once there are transactions to look at."
                )
            } else {
                ForEach(model.insights) { insight in
                    InsightCard(insight: insight)
                }
            }
        }
    }

    /// A tap on the donut reports a position along the running total; turn it into a category and open it.
    private func openCategory(at angleValue: Double?) {
        guard let angleValue else {
            return
        }
        let slices = model.derived.slices
        if let categoryID = CategoryDonutChart.categoryID(at: angleValue, in: slices) {
            drill = CategoryDrill(categoryID: categoryID, month: model.selectedMonth)
        }
        selectedAngle = nil
    }
}

/// Previous / next month with the month name between them.
struct MonthPickerBar: View {
    let title: String
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Previous month")
            .accessibilityIdentifier("previousMonthButton")
            Spacer()
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("selectedMonthLabel")
            Spacer()
            Button(action: onForward) {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            .disabled(!canGoForward)
            .accessibilityLabel("Next month")
            .accessibilityHint(canGoForward ? "" : "Already on the current month")
            .accessibilityIdentifier("nextMonthButton")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
