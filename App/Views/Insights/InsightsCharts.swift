// InsightsCharts.swift — the bar and line charts on the Insights tab (Swift Charts) and the top-merchants list.
// Core hands over Decimal values; they become Double only here, through Core's plotting accessors.

import SwiftUI
import Charts
import LedgerlyCore

// MARK: - Weekly spending vs earnings

private struct WeeklyPoint: Identifiable {
    let id: String
    let week: String
    let series: String
    let value: Double
    let spokenLabel: String
    let spokenValue: String
}

struct WeeklyBarsCard: View {
    let bars: [WeeklyBar]
    let calendar: LedgerCalendar

    var body: some View {
        CardView(title: "Spending and earnings by week") {
            if isEmpty {
                EmptyStateView(
                    title: "No weekly data yet",
                    systemImage: "chart.bar",
                    message: "Weekly spending and earnings show up here."
                )
            } else {
                chart
                Text("Weeks run Monday to Sunday. A week counts toward the month its Monday falls in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var isEmpty: Bool {
        !bars.contains { $0.spendingValue > 0 || $0.earnings != nil }
    }

    private var points: [WeeklyPoint] {
        var result: [WeeklyPoint] = []
        for bar in bars {
            let week = DateText.shortDay(bar.weekStart)
            let range = DateText.weekRange(weekStart: bar.weekStart, calendar: calendar)
            result.append(
                WeeklyPoint(
                    id: week + "-spending",
                    week: week,
                    series: "Spending",
                    value: bar.spendingValue,
                    spokenLabel: "Spending, week of " + range,
                    spokenValue: Money.string(bar.spending)
                )
            )
            let earningsText: String
            if let earnings = bar.earnings {
                earningsText = Money.string(earnings)
            } else {
                earningsText = "Not entered"
            }
            result.append(
                WeeklyPoint(
                    id: week + "-earnings",
                    week: week,
                    series: "Earnings",
                    value: bar.earningsValue,
                    spokenLabel: "Earnings, week of " + range,
                    spokenValue: earningsText
                )
            )
        }
        return result
    }

    private var chart: some View {
        let data = points
        return Chart(data) { point in
            BarMark(
                x: .value("Week of", point.week),
                y: .value("Amount", point.value)
            )
            .foregroundStyle(by: .value("Type", point.series))
            .position(by: .value("Type", point.series))
            .accessibilityLabel(point.spokenLabel)
            .accessibilityValue(point.spokenValue)
        }
        .chartForegroundStyleScale(domain: ["Spending", "Earnings"], range: [Color.orange, Color.green])
        .frame(height: 220)
        .accessibilityLabel("Bar chart of spending and earnings for each week")
    }
}

// MARK: - Cumulative spending vs on-track line

private struct LinePoint: Identifiable {
    let id: String
    let day: Int
    let series: String
    let value: Double
    let spokenLabel: String
    let spokenValue: String
}

struct CumulativeCard: View {
    let points: [CumulativePoint]

    var body: some View {
        CardView(title: "Spending vs on-track budget") {
            if !hasSpending {
                EmptyStateView(
                    title: "Nothing to plot yet",
                    systemImage: "chart.xyaxis.line",
                    message: "The running total of spending shows up here."
                )
            } else {
                chart
                if !hasOnTrack {
                    Text("Add your earnings to see the on-track budget line.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("The on-track line is expected income minus your goal, spread evenly over the month.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var hasSpending: Bool {
        points.contains { ($0.cumulativeValue ?? 0) > 0 }
    }

    private var hasOnTrack: Bool {
        points.contains { $0.onTrackValue != nil }
    }

    private var linePoints: [LinePoint] {
        var result: [LinePoint] = []
        for point in points {
            if let value = point.cumulativeValue, let amount = point.cumulativeSpending {
                result.append(
                    LinePoint(
                        id: "spent-\(point.day)",
                        day: point.day,
                        series: "Spent",
                        value: value,
                        spokenLabel: "Spent by day \(point.day)",
                        spokenValue: Money.string(amount)
                    )
                )
            }
        }
        for point in points {
            if let value = point.onTrackValue, let amount = point.onTrack {
                result.append(
                    LinePoint(
                        id: "track-\(point.day)",
                        day: point.day,
                        series: "On track",
                        value: value,
                        spokenLabel: "On-track budget by day \(point.day)",
                        spokenValue: Money.string(amount)
                    )
                )
            }
        }
        return result
    }

    private var chart: some View {
        let data = linePoints
        return Chart(data) { point in
            LineMark(
                x: .value("Day", point.day),
                y: .value("Amount", point.value)
            )
            .foregroundStyle(by: .value("Line", point.series))
            .lineStyle(by: .value("Line", point.series))
            .accessibilityLabel(point.spokenLabel)
            .accessibilityValue(point.spokenValue)
        }
        .chartForegroundStyleScale(domain: ["Spent", "On track"], range: [Color.orange, Color.green])
        .chartXAxisLabel("Day of month")
        .frame(height: 220)
        .accessibilityLabel("Line chart of cumulative spending against the on-track budget")
    }
}

// MARK: - Month over month by category

private struct ComparisonPoint: Identifiable {
    let id: String
    let category: String
    let series: String
    let value: Double
    let spokenLabel: String
    let spokenValue: String
}

struct MonthOverMonthCard: View {
    let comparisons: [CategoryComparison]
    let currentLabel: String
    let previousLabel: String

    var body: some View {
        CardView(title: "This month vs last month") {
            if visible.isEmpty {
                EmptyStateView(
                    title: "Nothing to compare yet",
                    systemImage: "chart.bar.xaxis",
                    message: "Category totals for this month and the month before show up here."
                )
            } else {
                chart
            }
        }
    }

    /// Categories with spending in at least one of the two months.
    private var visible: [CategoryComparison] {
        comparisons.filter { $0.currentValue > 0 || $0.previousValue > 0 }
    }

    private var points: [ComparisonPoint] {
        var result: [ComparisonPoint] = []
        for item in visible {
            result.append(
                ComparisonPoint(
                    id: item.id.uuidString + "-previous",
                    category: item.name,
                    series: previousLabel,
                    value: item.previousValue,
                    spokenLabel: item.name + ", " + previousLabel,
                    spokenValue: Money.string(item.previous)
                )
            )
            result.append(
                ComparisonPoint(
                    id: item.id.uuidString + "-current",
                    category: item.name,
                    series: currentLabel,
                    value: item.currentValue,
                    spokenLabel: item.name + ", " + currentLabel,
                    spokenValue: Money.string(item.current)
                )
            )
        }
        return result
    }

    private var chartHeight: CGFloat {
        CGFloat(max(visible.count, 2)) * 52
    }

    private var chart: some View {
        let data = points
        return Chart(data) { point in
            BarMark(
                x: .value("Amount", point.value),
                y: .value("Category", point.category)
            )
            .foregroundStyle(by: .value("Month", point.series))
            .position(by: .value("Month", point.series))
            .accessibilityLabel(point.spokenLabel)
            .accessibilityValue(point.spokenValue)
        }
        .chartForegroundStyleScale(domain: [previousLabel, currentLabel], range: [Color.gray, Color.accentColor])
        .frame(height: chartHeight)
        .accessibilityLabel("Grouped bar chart comparing each category with the month before")
    }
}

// MARK: - Top merchants

struct TopMerchantsCard: View {
    let merchants: [MerchantSpend]

    var body: some View {
        CardView(title: "Top merchants") {
            if merchants.isEmpty {
                EmptyStateView(
                    title: "No merchants yet",
                    systemImage: "storefront",
                    message: "The places you spend the most show up here."
                )
            } else {
                ForEach(merchants) { merchant in
                    TopMerchantRow(merchant: merchant)
                }
            }
        }
    }
}

private struct TopMerchantRow: View {
    let merchant: MerchantSpend

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(merchant.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Money.string(merchant.amount))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
            ProgressView(value: fraction)
                .tint(Color.accentColor)
                .accessibilityHidden(true)
            Text(changeText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(merchant.displayName), \(Money.string(merchant.amount)), \(changeText)")
    }

    private var fraction: Double {
        min(max(merchant.fractionOfTopValue, 0), 1)
    }

    private var changeText: String {
        let visits = merchant.transactionCount == 1 ? "1 purchase" : "\(merchant.transactionCount) purchases"
        if merchant.isNew {
            return visits + " · new this month"
        }
        let change = merchant.change
        if change > 0 {
            return visits + " · up " + Money.string(change) + " from last month"
        }
        if change < 0 {
            return visits + " · down " + Money.string(-change) + " from last month"
        }
        return visits + " · same as last month"
    }
}
