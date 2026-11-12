// MerchantRulesView.swift — the learned "always categorize this merchant as…" rules. Swipe to delete.

import SwiftUI
import LedgerlyCore

struct MerchantRulesView: View {
    @Environment(LedgerStore.self) private var store

    var body: some View {
        content
            .navigationTitle("Merchant Rules")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        let rules = store.data.rules
        if rules.isEmpty {
            EmptyStateView(
                title: "No rules yet",
                systemImage: "wand.and.stars",
                message: "Change a transaction's category and choose Always. Ledgerly will remember it for that merchant."
            )
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("rulesEmptyState")
        } else {
            List {
                Section {
                    ForEach(Array(rules.enumerated()), id: \.element.normalizedMerchant) { index, rule in
                        ruleRow(rule, index: index)
                    }
                    .onDelete { offsets in
                        delete(at: offsets, from: rules)
                    }
                } footer: {
                    Text("Rules win over the built-in keyword list. Swipe a rule to delete it.")
                }
            }
            .listStyle(.insetGrouped)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
    }

    private func ruleRow(_ rule: MerchantRule, index: Int) -> some View {
        let category = store.data.categories.first { $0.id == rule.categoryID }
        let categoryName = category?.name ?? "Other"
        return HStack(spacing: 12) {
            CategoryIcon(
                symbolName: category?.symbolName ?? "ellipsis.circle.fill",
                colorHex: category?.colorHex ?? "#868E96"
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.normalizedMerchant)
                    .font(.body)
                Text("Always \(categoryName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rule.normalizedMerchant), always \(categoryName)")
        .accessibilityIdentifier("rule_row_\(index)")
    }

    private func delete(at offsets: IndexSet, from rules: [MerchantRule]) {
        let merchants = offsets.map { rules[$0].normalizedMerchant }
        Task {
            for merchant in merchants {
                await store.deleteRule(normalizedMerchant: merchant)
            }
        }
    }
}
