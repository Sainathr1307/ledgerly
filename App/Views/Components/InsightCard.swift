// InsightCard.swift — one plain-English insight. The gap-closing plan card also lists each cut and the total.

import SwiftUI
import LedgerlyCore

struct InsightCard: View {
    let insight: Insight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(insight.title)
                    .font(.subheadline.weight(.semibold))
                Text(insight.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let plan = insight.gapPlan {
                    GapPlanList(plan: plan)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch insight.sentiment {
        case .warning:
            return .orange
        case .positive:
            return .green
        case .neutral:
            return .blue
        }
    }

    private var symbolName: String {
        switch insight.kind {
        case .missingIncome:
            return "questionmark.circle.fill"
        case .gapPlan:
            return "scissors"
        case .goalOnTrack:
            return "checkmark.seal.fill"
        case .goalMissed:
            return "flag.slash.fill"
        case .overPace:
            return "arrow.up.right.circle.fill"
        case .frequentSmallPurchases:
            return "cup.and.saucer.fill"
        case .topMerchants:
            return "storefront.fill"
        case .weekendVsWeekday:
            return "calendar"
        case .underUsual:
            return "arrow.down.right.circle.fill"
        case .incomeEstimated:
            return "info.circle.fill"
        }
    }
}

/// The cut list of a gap-closing plan: each cut with its amount, then the total.
struct GapPlanList: View {
    let plan: GapPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(plan.cuts) { cut in
                cutRow(cut)
            }
            if !plan.cuts.isEmpty {
                Divider()
                HStack {
                    Text("Total cuts")
                        .font(.footnote.weight(.semibold))
                    Spacer()
                    Text(Money.string(plan.totalCuts))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                }
            }
            if plan.uncovered > 0 {
                Text("\(Money.string(plan.uncovered)) of the gap can't be covered by trimming these categories.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    private func cutRow(_ cut: GapCut) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(cut.note)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(Money.string(cut.amount))
                    .font(.footnote)
                    .monospacedDigit()
            }
            if let suggestion = cut.suggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
