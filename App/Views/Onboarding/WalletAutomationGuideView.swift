// WalletAutomationGuideView.swift — how to set up the Shortcuts Wallet automation, what it can't do, and a "Test it" button.

import SwiftUI
import LedgerlyCore

struct WalletAutomationGuideView: View {
    @Environment(\.openURL) private var openURL

    @State private var isTesting = false
    @State private var testOutcome: TestOutcome?

    /// What the last tap on "Test it" produced.
    private struct TestOutcome {
        var succeeded: Bool
        /// One line: what was saved, or what went wrong. Shown under the button.
        var headline: String
        /// Second line: where to look for it.
        var detail: String
        /// Third line: what happened with the notification.
        var notificationNote: String
        /// The saved test transaction, so it can be removed again.
        var recordID: UUID?
    }

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro
                WalletAutomationStepsView()
                openShortcutsButton
                limitations
                testSection
            }
            .padding()
        }
        .navigationTitle("Wallet Automation")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Log Wallet purchases automatically")
                    .font(.title2.bold())
            } icon: {
                Image(systemName: "wave.3.right.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityAddTraits(.isHeader)

            Text("iOS doesn't let apps read your Wallet history. What it does offer is a Shortcuts automation that runs each time you tap a Wallet card to pay. Set it up once and it hands every purchase to Ledgerly. It takes about two minutes.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var openShortcutsButton: some View {
        Button {
            if let url = URL(string: "shortcuts://") {
                openURL(url)
            }
        } label: {
            Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("openShortcutsButton")
        .accessibilityHint("Opens the Shortcuts app so you can create the automation")
    }

    private var limitations: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("What this can't do", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
                .accessibilityAddTraits(.isHeader)

            limitationRow("It only fires when you tap to pay with a card in Wallet on this iPhone.")
            limitationRow("Online and in-app Apple Pay, payments from an Apple Watch or another device, and swiping or inserting the physical card are not captured. Add those by hand with the + button.")
            limitationRow("iOS sometimes sends an amount of 0 or leaves out the merchant. Those purchases are still saved and wait in Needs Review so you can fix them with a tap.")
            limitationRow("Ledgerly can't create the automation for you. Apple only lets you build it yourself in Shortcuts.")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func limitationRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "minus")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Test it", systemImage: "checkmark.seal")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text("This runs the same code as the automation with a sample purchase: $12.40 at Starbucks on a card called Test Card. It saves a real transaction, which you can remove again below.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                runTest()
            } label: {
                HStack {
                    if isTesting {
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                    Text(isTesting ? "Testing…" : "Test it")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isTesting)
            .accessibilityIdentifier("testWalletIntentButton")
            .accessibilityLabel("Test it")
            .accessibilityHint("Logs a sample purchase of $12.40 at Starbucks")

            if let outcome = testOutcome {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(outcome.headline)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("testWalletIntentResult")
                    } icon: {
                        Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(outcome.succeeded ? Color.green : Color.red)
                            .accessibilityHidden(true)
                    }

                    if !outcome.detail.isEmpty {
                        Text(outcome.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !outcome.notificationNote.isEmpty {
                        Text(outcome.notificationNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("testWalletIntentNotificationNote")
                    }
                    if let recordID = outcome.recordID {
                        Button(role: .destructive) {
                            removeTestTransaction(id: recordID)
                        } label: {
                            Label("Remove the test transaction", systemImage: "trash")
                        }
                        .font(.footnote)
                        .accessibilityIdentifier("removeTestTransactionButton")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
        }
    }

    // MARK: - Actions

    private func runTest() {
        guard !isTesting else { return }
        isTesting = true
        Task {
            let outcome = await WalletAutomationGuideView.performTest()
            testOutcome = outcome
            isTesting = false
        }
    }

    private func removeTestTransaction(id: UUID) {
        Task {
            do {
                try await LedgerRepository.shared.deleteTransaction(id: id)
                testOutcome = TestOutcome(
                    succeeded: true,
                    headline: "Test transaction removed.",
                    detail: "",
                    notificationNote: "",
                    recordID: nil
                )
            } catch {
                testOutcome = TestOutcome(
                    succeeded: false,
                    headline: "Couldn't remove the test transaction.",
                    detail: error.localizedDescription,
                    notificationNote: "You can delete it from the Transactions tab.",
                    recordID: nil
                )
            }
        }
    }

    /// Runs the exact path the App Intent uses, with sample data, and describes what happened.
    private static func performTest() async -> TestOutcome {
        do {
            let result = try await WalletTransactionLogger.log(
                amount: "$12.40",
                merchant: "Starbucks",
                cardName: "Test Card"
            )
            let record = result.record
            let money = MoneyFormat.string(record.amount, currencyCode: record.currencyCode)
            let headline = "Saved \(money) at \(record.merchant) · \(result.categoryName)"

            var detail = "Paid with \(record.paymentMethod.displayName). Look for it at the top of the Transactions tab."
            if record.isPossibleDuplicate {
                detail = "You ran the test twice within three minutes, so this one was flagged as a possible duplicate and put in Needs Review. That's the duplicate protection doing its job."
            } else if record.needsReview {
                detail = "It was saved, but flagged for review."
            }

            let note: String
            if LaunchFlags.isUITesting {
                note = "Notifications are skipped while UI tests run."
            } else if await NotificationService.isAuthorized() {
                note = "A notification was posted: \"\(result.notificationBody)\""
            } else {
                note = "No notification was shown because notifications are turned off for Ledgerly. Purchases are still logged. To get the confirmations, allow notifications in the Settings app under Notifications, Ledgerly."
            }
            return TestOutcome(
                succeeded: true,
                headline: headline,
                detail: detail,
                notificationNote: note,
                recordID: record.id
            )
        } catch {
            return TestOutcome(
                succeeded: false,
                headline: "The test transaction couldn't be saved.",
                detail: error.localizedDescription,
                notificationNote: "",
                recordID: nil
            )
        }
    }
}

#Preview {
    NavigationStack {
        WalletAutomationGuideView()
    }
}
