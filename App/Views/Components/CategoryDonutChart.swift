// CategoryDonutChart.swift — donut of spending by category (Swift Charts), used on Home and Insights.

import SwiftUI
import Charts
import LedgerlyCore

/// One donut slice, with its strings already formatted.
struct DonutDatum: Identifiable {
    let id: UUID
    let name: String
    let value: Double
    let color: Color
    let spokenValue: String
}

struct CategoryDonutChart: View {
    let slices: [CategorySlice]
    let totalText: String
    /// Set by Insights to make the chart itself tappable; nil on Home.
    var angleSelection: Binding<Double?>? = nil

    var body: some View {
        ZStack {
            chart
            VStack(spacing: 2) {
                Text("Spent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(totalText)
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 60)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: 220)
    }

    private var data: [DonutDatum] {
        slices.map { slice in
            DonutDatum(
                id: slice.id,
                name: slice.name,
                value: slice.value,
                color: Color(hex: slice.colorHex),
                spokenValue: Money.string(slice.amount) + ", " + MoneyFormat.percent(slice.fraction)
            )
        }
    }

    @ViewBuilder
    private var chart: some View {
        if let angleSelection {
            baseChart
                .chartAngleSelection(value: angleSelection)
        } else {
            baseChart
        }
    }

    private var baseChart: some View {
        let points = data
        return Chart(points) { point in
            SectorMark(
                angle: .value("Amount", point.value),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(point.color)
            .accessibilityLabel(point.name)
            .accessibilityValue(point.spokenValue)
        }
        .chartLegend(.hidden)
        .accessibilityLabel("Spending by category, total \(totalText)")
    }

    /// The category whose slice covers `angleValue` (a running total of slice values, as Charts reports it).
    static func categoryID(at angleValue: Double, in slices: [CategorySlice]) -> UUID? {
        var runningTotal: Double = 0
        for slice in slices {
            runningTotal += slice.value
            if angleValue <= runningTotal {
                return slice.categoryID
            }
        }
        return slices.last?.categoryID
    }
}

/// A legend row: color dot, name, share and amount.
struct CategoryLegendRow: View {
    let slice: CategorySlice

    var body: some View {
        HStack(spacing: 10) {
            CategoryIcon(symbolName: slice.symbolName, colorHex: slice.colorHex)
            Text(slice.name)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(MoneyFormat.percent(slice.fraction))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(Money.string(slice.amount))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(slice.name), \(Money.string(slice.amount)), \(MoneyFormat.percent(slice.fraction)) of spending")
    }
}
