// WalletAutomationStepsView.swift — the numbered step cards for setting up the Shortcuts Wallet automation (shared by onboarding and Settings).

import SwiftUI

/// One step of the walkthrough.
struct WalletAutomationStep: Identifiable, Hashable, Sendable {
    let number: Int
    let symbolName: String
    let title: String
    let detail: String

    var id: Int { number }

    /// The whole walkthrough, in order. The README repeats these steps; keep the two in sync.
    static let all: [WalletAutomationStep] = [
        WalletAutomationStep(
            number: 1,
            symbolName: "square.on.square",
            title: "Open the Shortcuts app",
            detail: "It comes with every iPhone. If you deleted it, get it back from the App Store first."
        ),
        WalletAutomationStep(
            number: 2,
            symbolName: "clock",
            title: "Go to the Automation tab",
            detail: "It's the middle tab at the bottom of the screen."
        ),
        WalletAutomationStep(
            number: 3,
            symbolName: "plus",
            title: "Tap + to make a new automation",
            detail: "The + is in the top right corner. If this is your first automation, tap New Automation instead."
        ),
        WalletAutomationStep(
            number: 4,
            symbolName: "wallet.pass",
            title: "Choose Transaction",
            detail: "Scroll down the list or search for it. On newer versions of iOS it is called Wallet."
        ),
        WalletAutomationStep(
            number: 5,
            symbolName: "creditcard",
            title: "Choose your cards",
            detail: "Tick every card you want Ledgerly to track. You can leave the merchant and category filters on their defaults so every purchase is caught."
        ),
        WalletAutomationStep(
            number: 6,
            symbolName: "bolt.fill",
            title: "Pick Run Immediately",
            detail: "Also turn off Notify When Run, otherwise iOS asks you to confirm every single time. Then tap Next."
        ),
        WalletAutomationStep(
            number: 7,
            symbolName: "doc.badge.plus",
            title: "Tap New Blank Automation",
            detail: "This opens an empty shortcut that runs whenever you pay."
        ),
        WalletAutomationStep(
            number: 8,
            symbolName: "magnifyingglass",
            title: "Add the Log Wallet Transaction action",
            detail: "Search for Ledgerly in the action search field, then tap Log Wallet Transaction."
        ),
        WalletAutomationStep(
            number: 9,
            symbolName: "arrow.triangle.branch",
            title: "Map Shortcut Input to Amount, Merchant and Card",
            detail: "Tap the Amount field in the action and choose Shortcut Input. Tap the Shortcut Input bubble again and pick Amount. Do the same for Merchant (pick Merchant) and for Card (pick Card or Pass)."
        ),
        WalletAutomationStep(
            number: 10,
            symbolName: "checkmark.circle.fill",
            title: "Tap Done",
            detail: "That's it. The next time you tap one of those cards to pay, the purchase shows up in Ledgerly with a notification."
        )
    ]
}

/// The list of step cards. Has no scroll view of its own, so it can be dropped into any scrolling screen.
struct WalletAutomationStepsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(WalletAutomationStep.all) { step in
                WalletAutomationStepCard(step: step)
            }
        }
    }
}

private struct WalletAutomationStepCard: View {
    let step: WalletAutomationStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(step.number)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(10)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(step.title)
                        .font(.headline)
                } icon: {
                    Image(systemName: step.symbolName)
                        .foregroundStyle(Color.accentColor)
                }
                Text(step.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.number) of \(WalletAutomationStep.all.count): \(step.title)")
        .accessibilityValue(step.detail)
    }
}
