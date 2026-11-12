// SettingsView.swift — the Settings tab: goal, earnings reminder, categories and rules, Wallet guide,
// CSV import/export, app lock, and erase all data.

import SwiftUI
import UIKit
import UserNotifications
import LedgerlyCore

struct SettingsView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(SheetCoordinator.self) private var sheets
    @Environment(\.openURL) private var openURL

    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var isExporting = false
    @State private var isEraseDialogPresented = false
    @State private var isReloadingDemo = false

    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        NavigationStack {
            Form {
                goalSection
                organizeSection
                reminderSection
                walletSection
                dataSection
                securitySection
                #if FINANCEKIT_ENABLED
                FinanceKitSettingsSection()
                #endif
                #if DEBUG
                debugSection
                #endif
                eraseSection
            }
            .navigationTitle("Settings")
            .task {
                await refreshNotificationStatus()
            }
            .confirmationDialog(
                "Erase all data?",
                isPresented: $isEraseDialogPresented,
                titleVisibility: .visible
            ) {
                Button("Erase Everything", role: .destructive) {
                    eraseEverything()
                }
                .accessibilityIdentifier("confirmEraseButton")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes every transaction, earnings entry, goal, rule and custom category from this iPhone. It can't be undone.")
            }
        }
    }

    // MARK: - Goal

    private var goalSection: some View {
        Section("Monthly savings goal") {
            Button {
                sheets.active = .goalEdit
            } label: {
                HStack {
                    Text("Goal for this month")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(Money.compact(store.current.goal))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Goal for this month, \(Money.compact(store.current.goal))")
            .accessibilityHint("Opens the goal editor")
            .accessibilityIdentifier("settingsGoalRow")
        }
    }

    // MARK: - Categories and rules

    private var organizeSection: some View {
        Section("Categories and rules") {
            NavigationLink {
                CategoriesEditorView()
            } label: {
                Label("Categories", systemImage: "square.grid.2x2")
            }
            .accessibilityIdentifier("settingsCategories")
            NavigationLink {
                MerchantRulesView()
            } label: {
                HStack {
                    Label("Merchant rules", systemImage: "wand.and.stars")
                    Spacer()
                    Text("\(store.data.rules.count)")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("settingsMerchantRules")
        }
    }

    // MARK: - Earnings reminder

    private var reminderSection: some View {
        Section {
            Button {
                sheets.active = .earnings
            } label: {
                Label("Weekly earnings", systemImage: "dollarsign.circle")
            }
            .accessibilityIdentifier("settingsEarnings")
            DatePicker(
                "Monday reminder time",
                selection: reminderTime,
                displayedComponents: [.hourAndMinute]
            )
            .accessibilityIdentifier("reminderTimePicker")
            reminderPermissionNote
        } header: {
            Text("Weekly earnings")
        } footer: {
            Text("Every Monday Ledgerly asks what you earned last week. The card on Home appears either way.")
        }
    }

    @ViewBuilder
    private var reminderPermissionNote: some View {
        if notificationStatus == .denied {
            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications are turned off for Ledgerly, so the Monday reminder can't be shown.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .font(.footnote)
                .accessibilityIdentifier("openSystemSettingsButton")
            }
        } else if notificationStatus == .notDetermined {
            Button("Turn on the Monday reminder") {
                Task {
                    _ = await NotificationService.requestAuthorization()
                    await rescheduleReminder()
                    await refreshNotificationStatus()
                }
            }
            .accessibilityIdentifier("enableReminderButton")
        }
    }

    /// The reminder time as a `Date` (today at the stored hour and minute) for the picker.
    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                let calendar = Calendar.current
                let today = Date()
                return calendar.date(
                    bySettingHour: settings.reminderHour,
                    minute: settings.reminderMinute,
                    second: 0,
                    of: today
                ) ?? today
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.reminderHour = parts.hour ?? 8
                settings.reminderMinute = parts.minute ?? 0
                Task {
                    await rescheduleReminder()
                }
            }
        )
    }

    private func rescheduleReminder() async {
        await NotificationService.scheduleWeeklyEarningsReminder(
            hour: settings.reminderHour,
            minute: settings.reminderMinute
        )
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await NotificationService.authorizationStatus()
    }

    // MARK: - Wallet

    private var walletSection: some View {
        Section {
            NavigationLink {
                WalletAutomationGuideView()
            } label: {
                Label("Wallet automation guide", systemImage: "wallet.pass")
            }
            .accessibilityIdentifier("settingsWalletGuide")
        } header: {
            Text("Apple Wallet")
        } footer: {
            Text("Set up the Shortcuts automation that logs card payments, and test it.")
        }
    }

    // MARK: - Import and export

    private var dataSection: some View {
        Section("Import and export") {
            NavigationLink {
                CSVImportView()
            } label: {
                Label("Import a CSV file", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("settingsImportCSV")
            Button {
                prepareExport()
            } label: {
                Label(isExporting ? "Preparing export…" : "Export all transactions as CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(isExporting)
            .accessibilityIdentifier("settingsExportCSV")
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share \(exportURL.lastPathComponent)", systemImage: "doc.text")
                }
                .accessibilityIdentifier("shareExportLink")
            }
            if let exportError {
                Text(exportError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func prepareExport() {
        isExporting = true
        exportError = nil
        Task {
            do {
                exportURL = try await CSVExporter.makeExportFile()
            } catch {
                exportURL = nil
                exportError = "Couldn't create the export file. \(error.localizedDescription)"
            }
            isExporting = false
        }
    }

    // MARK: - App lock

    private var securitySection: some View {
        Section {
            Toggle("Require Face ID to open", isOn: Bindable(settings).faceIDLockEnabled)
                .disabled(!AppLockService.canAuthenticate())
                .accessibilityIdentifier("faceIDLockToggle")
        } header: {
            Text("Privacy")
        } footer: {
            Text(AppLockService.canAuthenticate()
                 ? "Locks Ledgerly whenever it goes to the background. Your passcode works too."
                 : "Set up Face ID or a passcode on this iPhone to use the app lock.")
        }
    }

    // MARK: - Debug

    #if DEBUG
    private var debugSection: some View {
        Section {
            Button {
                isReloadingDemo = true
                Task {
                    await DemoDataSeeder.reload()
                    await store.reload()
                    isReloadingDemo = false
                }
            } label: {
                Label(isReloadingDemo ? "Reloading…" : "Reload demo data", systemImage: "arrow.clockwise")
            }
            .disabled(isReloadingDemo)
            .accessibilityIdentifier("reloadDemoDataButton")
        } header: {
            Text("Debug builds only")
        } footer: {
            Text("Replaces everything with three months of sample data.")
        }
    }
    #endif

    // MARK: - Erase

    private var eraseSection: some View {
        Section {
            Button("Erase All Data", role: .destructive) {
                isEraseDialogPresented = true
            }
            .accessibilityIdentifier("eraseAllDataButton")
        }
    }

    private func eraseEverything() {
        Task {
            await store.eraseAll()
            settings.resetAll()
            // Erasing is not a reinstall: skip onboarding, and don't let DEBUG builds re-seed the demo data.
            settings.hasCompletedOnboarding = true
            settings.demoDataLoaded = true
            exportURL = nil
            await rescheduleReminder()
            await store.reload()
        }
    }
}
