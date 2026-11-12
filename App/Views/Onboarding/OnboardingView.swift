// OnboardingView.swift — first-run flow: what the app does, the Wallet automation walkthrough, and the notification permission.

import SwiftUI

struct OnboardingView: View {
    private let onFinish: () -> Void

    @State private var page: Page = .welcome
    @State private var isRequestingPermission = false
    @State private var permissionAnswer: PermissionAnswer?

    private enum Page: Int, CaseIterable {
        case welcome, wallet, notifications, done
    }

    private enum PermissionAnswer {
        case granted, declined
    }

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                switch page {
                case .welcome:
                    welcomePage
                case .wallet:
                    WalletAutomationGuideView()
                case .notifications:
                    notificationsPage
                case .done:
                    donePage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
        .background(Color(.systemBackground))
        .accessibilityIdentifier("onboardingView")
    }

    // MARK: - Bars

    private var topBar: some View {
        HStack {
            if page != .welcome {
                Button {
                    goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .accessibilityIdentifier("onboardingBackButton")
            }
            Spacer()
            Text("Step \(page.rawValue + 1) of \(Page.allCases.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if page != .done {
                Button("Skip") {
                    onFinish()
                }
                .accessibilityIdentifier("onboardingSkipButton")
                .accessibilityHint("Skips the introduction. The Wallet guide is also in Settings.")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 10) {
            switch page {
            case .welcome:
                primaryButton("Continue", identifier: "onboardingContinueButton") {
                    page = .wallet
                }
            case .wallet:
                primaryButton("Continue", identifier: "onboardingContinueButton") {
                    page = .notifications
                }
                Text("You can do this later. The same guide is in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .notifications:
                if permissionAnswer == nil {
                    primaryButton(
                        isRequestingPermission ? "Asking…" : "Turn On Notifications",
                        identifier: "onboardingAllowNotificationsButton"
                    ) {
                        requestNotifications()
                    }
                    .disabled(isRequestingPermission)

                    Button("Not now") {
                        permissionAnswer = .declined
                        page = .done
                    }
                    .disabled(isRequestingPermission)
                    .accessibilityIdentifier("onboardingNotNowButton")
                    .accessibilityHint("Continues without notifications. The app still works.")
                } else {
                    primaryButton("Continue", identifier: "onboardingContinueButton") {
                        page = .done
                    }
                }
            case .done:
                primaryButton("Get Started", identifier: "onboardingFinishButton") {
                    onFinish()
                }
            }
        }
        .padding()
    }

    private func primaryButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "chart.pie.fill")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                Text("Welcome to Ledgerly")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)

                Text("One place for every purchase, so you can see where your money goes and what to cut to hit your savings goal.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                featureRow(
                    symbol: "plus.circle.fill",
                    title: "Add a purchase in seconds",
                    detail: "Type the amount, tap a category, save."
                )
                featureRow(
                    symbol: "tag.fill",
                    title: "Sorted for you",
                    detail: "Purchases are put into categories automatically, and the app learns from your corrections."
                )
                featureRow(
                    symbol: "target",
                    title: "A monthly savings goal",
                    detail: "See what you can safely spend each day, and exactly where to cut back if you're falling short."
                )
                featureRow(
                    symbol: "lock.fill",
                    title: "Private",
                    detail: "Everything stays on this iPhone. No account, no tracking, no internet connection."
                )

                VStack(alignment: .leading, spacing: 8) {
                    Label("One thing to know up front", systemImage: "info.circle.fill")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text("Apple doesn't let any app read your Wallet transactions on its own. Ledgerly gets them through a small Shortcuts automation that you set up once. The next screen shows how. It catches tap-to-pay purchases made with this iPhone; anything else, like cash or online orders, you add by hand.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .padding()
        }
    }

    private func featureRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var notificationsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "bell.badge.fill")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                Text("Two kinds of notification")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)

                featureRow(
                    symbol: "creditcard.fill",
                    title: "A confirmation after each Wallet purchase",
                    detail: "For example: Logged $12.40 at Starbucks · Food & Dining. If something is missing, it tells you to review it."
                )
                featureRow(
                    symbol: "calendar",
                    title: "A reminder every Monday morning",
                    detail: "New week! What did you earn last week? You can change the time in Settings."
                )

                Text("That's all Ledgerly will ever send. If you'd rather not get notifications, the app still works: purchases are logged silently and a card on the Home screen asks for last week's earnings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let answer = permissionAnswer {
                    Label {
                        Text(answer == .granted
                             ? "Notifications are on."
                             : "Notifications are off. You can turn them on later in the Settings app.")
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: answer == .granted ? "checkmark.circle.fill" : "bell.slash.fill")
                            .foregroundStyle(answer == .granted ? Color.green : Color.secondary)
                            .accessibilityHidden(true)
                    }
                    .accessibilityIdentifier("onboardingNotificationStatus")
                }
            }
            .padding()
        }
    }

    private var donePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(Color.green)
                    .accessibilityHidden(true)

                Text("You're set")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)

                Text("Next you'll pick how much you want to save this month. After that, add purchases with the + button, or let the Wallet automation bring them in.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                featureRow(
                    symbol: "wave.3.right.circle.fill",
                    title: "Haven't set up the automation yet?",
                    detail: "The guide and the Test it button are in Settings under Wallet Automation."
                )
                featureRow(
                    symbol: "tray.full.fill",
                    title: "Needs Review",
                    detail: "Purchases that arrive without an amount or a merchant wait there until you fill in the blank."
                )
            }
            .padding()
        }
    }

    // MARK: - Actions

    private func goBack() {
        guard let previous = Page(rawValue: page.rawValue - 1) else { return }
        page = previous
    }

    private func requestNotifications() {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        Task {
            let granted = await NotificationService.requestAuthorization()
            if granted {
                // Schedule the Monday reminder right away at the time saved in Settings (8:00 by default).
                let hour = AppSettings.shared.reminderHour
                let minute = AppSettings.shared.reminderMinute
                await NotificationService.scheduleWeeklyEarningsReminder(hour: hour, minute: minute)
            }
            permissionAnswer = granted ? .granted : .declined
            isRequestingPermission = false
        }
    }
}
