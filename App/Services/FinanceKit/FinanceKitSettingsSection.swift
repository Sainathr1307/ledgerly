// FinanceKitSettingsSection.swift — Settings rows for the optional FinanceKit source; compiled only with the FINANCEKIT_ENABLED flag.

#if FINANCEKIT_ENABLED && canImport(FinanceKit)
import SwiftUI

struct FinanceKitSettingsSection: View {
    @State private var isSyncing = false
    @State private var message: String?

    init() {}

    var body: some View {
        @Bindable var settings = AppSettings.shared

        Section {
            Toggle("Apple Card, Cash and Savings", isOn: $settings.financeKitEnabled)
                .accessibilityIdentifier("financeKitToggle")
                .accessibilityHint("Lets Ledgerly import transactions from your Apple accounts")

            Button {
                sync()
            } label: {
                HStack {
                    if isSyncing {
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                    Text(isSyncing ? "Syncing…" : "Sync now")
                }
            }
            .disabled(!settings.financeKitEnabled || isSyncing)
            .accessibilityIdentifier("financeKitSyncButton")

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("financeKitSyncMessage")
            }
        } header: {
            Text("Apple accounts (FinanceKit)")
        } footer: {
            Text("Off by default. Imports Apple Card, Apple Cash and Savings transactions straight from Wallet. US only. The data stays on this iPhone.")
        }
    }

    private func sync() {
        guard !isSyncing else { return }
        isSyncing = true
        message = nil
        Task {
            do {
                let count = try await FinanceKitSync.syncNow()
                message = count == 1 ? "Added 1 transaction." : "Added \(count) transactions."
            } catch {
                message = error.localizedDescription
            }
            isSyncing = false
        }
    }
}
#endif
