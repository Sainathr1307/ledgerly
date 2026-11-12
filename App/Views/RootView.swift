// RootView.swift — decides what the window shows (loading, lock screen, onboarding or the tabs) and runs the launch tasks.

import SwiftUI
import LedgerlyCore

/// The sheets the main screen can present. One at a time.
enum MainSheet: String, Identifiable {
    /// The monthly "How much do you want to save?" prompt (first launch / new month).
    case goalPrompt
    /// The same sheet opened by the user from Home or Settings.
    case goalEdit
    case earnings
    case review

    var id: String { rawValue }
}

@MainActor
@Observable
final class SheetCoordinator {
    var active: MainSheet?
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = LedgerStore()
    @State private var sheets = SheetCoordinator()
    @State private var didBootstrap = false
    @State private var didForceGoalPrompt = false

    private var router: AppRouter { AppRouter.shared }
    private var settings: AppSettings { AppSettings.shared }
    private var lock: AppLockService { AppLockService.shared }

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                startupErrorBanner
            }
            .environment(store)
            .environment(sheets)
            .preferredColorScheme(UITestFlags.forceDark ? ColorScheme.dark : nil)
            .task {
                await bootstrap()
            }
            .onReceive(NotificationCenter.default.publisher(for: .ledgerDidChange)) { _ in
                store.requestReload()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhase(newPhase)
            }
            .onChange(of: lock.isLocked) { _, isLocked in
                if !isLocked {
                    promptForGoalIfNeeded()
                }
            }
            .alert("Something went wrong", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if lock.isLocked {
            // The tabs are removed while locked, so no sheet with data can stay on top of the lock screen.
            LockScreenView(lock: lock)
        } else if !store.hasLoaded {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !settings.hasCompletedOnboarding && !LaunchFlags.isUITesting {
            OnboardingView(onFinish: {
                finishOnboarding()
            })
        } else {
            MainTabView()
        }
    }

    @ViewBuilder
    private var startupErrorBanner: some View {
        if let message = SharedModelContainer.startupError {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.yellow.opacity(0.3))
                .accessibilityIdentifier("startupErrorBanner")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { isShown in
                if !isShown {
                    store.errorMessage = nil
                }
            }
        )
    }

    // MARK: - Launch

    private func bootstrap() async {
        if didBootstrap {
            return
        }
        didBootstrap = true

        await store.seedDefaultCategories()
        #if DEBUG
        await DemoDataSeeder.seedIfNeeded()
        if LaunchFlags.isUITesting && UITestFlags.loadDemoData {
            await DemoDataSeeder.reload()
        }
        #endif
        await store.reload()
        if LaunchFlags.isUITesting && LaunchFlags.seedReviewItem {
            await store.seedReviewItemForUITests()
        }

        // No-op when notification permission has not been granted.
        await NotificationService.scheduleWeeklyEarningsReminder(
            hour: settings.reminderHour,
            minute: settings.reminderMinute
        )
        promptForGoalIfNeeded()
    }

    private func finishOnboarding() {
        settings.hasCompletedOnboarding = true
        Task {
            await NotificationService.scheduleWeeklyEarningsReminder(
                hour: settings.reminderHour,
                minute: settings.reminderMinute
            )
        }
        promptForGoalIfNeeded()
    }

    /// Shows the monthly goal sheet on first launch and on the first open of each new month.
    private func promptForGoalIfNeeded() {
        guard store.hasLoaded, !lock.isLocked else {
            return
        }
        if LaunchFlags.isUITesting {
            guard LaunchFlags.forceGoalPrompt, !didForceGoalPrompt else {
                return
            }
            didForceGoalPrompt = true
            sheets.active = .goalPrompt
            return
        }
        guard settings.hasCompletedOnboarding else {
            return
        }
        let now = Date()
        let calendar = LedgerCalendar.current
        let shouldPrompt = GoalPrompt.shouldPrompt(
            lastPromptMonth: settings.lastGoalPromptMonth,
            now: now,
            calendar: calendar
        )
        if shouldPrompt {
            settings.lastGoalPromptMonth = GoalPrompt.monthString(now: now, calendar: calendar)
            router.isAddSheetPresented = false
            sheets.active = .goalPrompt
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            lock.lockIfEnabled()
        case .active:
            if didBootstrap {
                store.requestReload()
                promptForGoalIfNeeded()
            }
        default:
            break
        }
    }
}
