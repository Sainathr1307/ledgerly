// HomeCards.swift — the cards at the top of Home: earnings needed, Needs Review, and goal progress.

import SwiftUI
import LedgerlyCore

/// "What did you earn last week?" — stays until last week's earnings are entered, with or without notifications.
struct EarningsNeededCard: View {
    let weekText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What did you earn last week?")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text("Add your earnings for \(weekText).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What did you earn last week? Add your earnings for \(weekText).")
        .accessibilityHint("Opens weekly earnings")
        .accessibilityIdentifier("earningsCard")
    }
}

/// "3 transactions need review".
struct NeedsReviewBanner: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color.orange, in: Capsule())
                    .accessibilityHidden(true)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(message)
        .accessibilityHint("Opens the Needs Review inbox")
        .accessibilityIdentifier("needsReviewBanner")
    }

    private var message: String {
        count == 1 ? "1 transaction needs review" : "\(count) transactions need review"
    }
}

/// Goal ring, projected savings and safe-to-spend per day.
struct GoalProgressCard: View {
    let snapshot: BudgetSnapshot
    let onEditGoal: () -> Void
    let onAddEarnings: () -> Void

    var body: some View {
        CardView {
            HStack(alignment: .center, spacing: 16) {
                GoalRing(progress: snapshot.goalProgressValue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Savings goal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Money.compact(snapshot.goal))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .accessibilityLabel("Savings goal \(Money.compact(snapshot.goal))")
                        .accessibilityIdentifier("goalAmountLabel")
                    Button("Change goal", action: onEditGoal)
                        .font(.footnote)
                        .accessibilityIdentifier("editGoalButton")
                }
                Spacer(minLength: 0)
            }
            Divider()
            if snapshot.incomeBasis == .unknown {
                incomeGap
            } else {
                numbers
            }
        }
    }

    /// Shown instead of guessed numbers when no earnings have been entered at all.
    private var incomeGap: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Add your earnings to see this", systemImage: "questionmark.circle")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("incomeGapNotice")
            Text("Projected savings and safe-to-spend need at least one week of earnings. Spent so far: \(Money.string(snapshot.spent)).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add earnings", action: onAddEarnings)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("addEarningsButton")
        }
    }

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let safe = snapshot.safeToSpendPerDay {
                HomeStatRow(
                    title: snapshot.isPastMonth ? "Safe to spend (month over)" : "Safe to spend per day",
                    value: Money.string(safe),
                    detail: snapshot.isPastMonth ? nil : daysLeftText,
                    identifier: "safeToSpendLabel"
                )
            }
            if let projected = snapshot.projectedSavings {
                HomeStatRow(
                    title: "Projected savings at month-end",
                    value: Money.string(projected),
                    detail: onTrackText,
                    identifier: "projectedSavingsLabel"
                )
            }
            HomeStatRow(
                title: "Spent so far",
                value: Money.string(snapshot.spent),
                detail: incomeText,
                identifier: "spentLabel"
            )
        }
    }

    private var daysLeftText: String {
        snapshot.daysLeft == 1 ? "1 day left, today included" : "\(snapshot.daysLeft) days left, today included"
    }

    private var onTrackText: String? {
        guard let onTrack = snapshot.isOnTrack else {
            return nil
        }
        return onTrack ? "On track for your goal" : "Below your goal"
    }

    private var incomeText: String? {
        guard let expected = snapshot.expectedIncome else {
            return nil
        }
        let prefix = snapshot.incomeBasis == .estimatedFromHistory ? "Estimated income " : "Expected income "
        return prefix + Money.string(expected)
    }
}

/// One labelled number on the goal card.
struct HomeStatRow: View {
    let title: String
    let value: String
    let detail: String?
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
        .accessibilityIdentifier(identifier)
    }

    private var spokenText: String {
        if let detail {
            return title + ", " + value + ", " + detail
        }
        return title + ", " + value
    }
}

/// The progress ring: projected savings as a share of the goal.
struct GoalRing: View {
    let progress: Double?

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(uiColor: .systemFill), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(clamped))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(centerText)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 12)
        }
        .frame(width: 84, height: 84)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Goal progress")
        .accessibilityValue(spokenValue)
    }

    private var clamped: Double {
        min(max(progress ?? 0, 0), 1)
    }

    private var percent: Int {
        Int((clamped * 100).rounded())
    }

    private var centerText: String {
        progress == nil ? "—" : "\(percent)%"
    }

    private var spokenValue: String {
        progress == nil ? "Unknown until earnings are added" : "\(percent) percent of the goal, based on projected savings"
    }
}
