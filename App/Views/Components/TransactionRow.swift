// TransactionRow.swift — one transaction in a list: icon, merchant, details, badges and amount.

import SwiftUI
import LedgerlyCore

struct TransactionRow: View {
    let record: TransactionRecord
    let category: CategoryRecord?
    var showsDate: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CategoryIcon(
                symbolName: category?.symbolName ?? "ellipsis.circle.fill",
                colorHex: category?.colorHex ?? "#868E96"
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                badges
            }
            Spacer(minLength: 8)
            AmountText(amount: record.amount)
                .font(.body.weight(.medium))
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    private var categoryName: String {
        category?.name ?? "Other"
    }

    private var title: String {
        MerchantNormalizer.isBlank(record.merchant) ? categoryName : record.merchant
    }

    private var subtitle: String {
        var parts: [String] = []
        if !MerchantNormalizer.isBlank(record.merchant) {
            parts.append(categoryName)
        }
        parts.append(record.paymentMethod.displayName)
        parts.append(showsDate ? DateText.dayAndTime(record.date) : DateText.time(record.date))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var badges: some View {
        if record.needsReview || record.isPossibleDuplicate || record.isRefund {
            HStack(spacing: 6) {
                if record.needsReview {
                    BadgeLabel(text: "Needs review", systemImage: "exclamationmark.circle.fill", tint: .orange)
                }
                if record.isPossibleDuplicate {
                    BadgeLabel(text: "Possible duplicate", systemImage: "doc.on.doc.fill", tint: .red)
                }
                if record.isRefund {
                    BadgeLabel(text: "Refund", systemImage: "arrow.uturn.backward", tint: .green)
                }
            }
        }
    }

    private var spokenSummary: String {
        var parts: [String] = []
        parts.append(MerchantNormalizer.isBlank(record.merchant) ? "No merchant" : record.merchant)
        if record.amount < 0 {
            parts.append("refund " + Money.string(-record.amount))
        } else {
            parts.append(Money.string(record.amount))
        }
        parts.append(categoryName)
        parts.append(record.paymentMethod.displayName)
        parts.append(DateText.dayAndTime(record.date))
        if record.needsReview {
            parts.append("needs review")
        }
        if record.isPossibleDuplicate {
            parts.append("possible duplicate")
        }
        return parts.joined(separator: ", ")
    }
}
