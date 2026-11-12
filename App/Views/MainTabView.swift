// MainTabView.swift — the four tabs, the custom tab bar with the centre (+) button, and the app-level sheets.

import SwiftUI
import LedgerlyCore

struct MainTabView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(SheetCoordinator.self) private var sheets

    private var router: AppRouter { AppRouter.shared }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                tabContainer(.home) { HomeView() }
                tabContainer(.transactions) { TransactionsView() }
                tabContainer(.insights) { InsightsView() }
                tabContainer(.settings) { SettingsView() }
            }
            AppTabBar(
                selection: router.selectedTab,
                onSelect: { tab in router.selectedTab = tab },
                onAdd: { router.isAddSheetPresented = true }
            )
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: Bindable(router).isAddSheetPresented) {
            TransactionEditorSheet(store: store, editing: nil)
        }
        .sheet(
            item: Bindable(sheets).active,
            onDismiss: {
                sheetDismissed()
            },
            content: { sheet in
                sheetContent(sheet)
            }
        )
        .onChange(of: router.pendingDestination, initial: true) { _, destination in
            handle(destination)
        }
    }

    /// Every tab stays alive (so scroll position and search text survive a tab switch); only the selected one is visible.
    private func tabContainer<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        let isSelected = router.selectedTab == tab
        return content()
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }

    @ViewBuilder
    private func sheetContent(_ sheet: MainSheet) -> some View {
        switch sheet {
        case .goalPrompt:
            GoalSheet(store: store, isMonthlyPrompt: true)
        case .goalEdit:
            GoalSheet(store: store, isMonthlyPrompt: false)
        case .earnings:
            EarningsView(store: store)
        case .review:
            NeedsReviewView()
        }
    }

    /// Closing the goal sheet without saving still leaves a goal for the month (the pre-filled default).
    private func sheetDismissed() {
        Task {
            await store.ensureCurrentGoal()
        }
    }

    private func handle(_ destination: AppRouter.Destination?) {
        guard let destination else {
            return
        }
        switch destination {
        case .earnings:
            router.selectedTab = .home
            sheets.active = .earnings
        case .review:
            router.selectedTab = .home
            sheets.active = .review
        case .transactions:
            router.selectedTab = .transactions
        }
        router.pendingDestination = nil
    }
}

/// The bottom bar: Home, Transactions, (+), Insights, Settings.
struct AppTabBar: View {
    let selection: AppTab
    let onSelect: (AppTab) -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            tabButton(.home, title: "Home", systemImage: "house.fill", identifier: "tab_home")
            tabButton(.transactions, title: "Transactions", systemImage: "list.bullet", identifier: "tab_transactions")
            addButton
            tabButton(.insights, title: "Insights", systemImage: "chart.pie.fill", identifier: "tab_insights")
            tabButton(.settings, title: "Settings", systemImage: "gearshape.fill", identifier: "tab_settings")
        }
        .padding(.top, 6)
        .padding(.horizontal, 4)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func tabButton(_ tab: AppTab, title: String, systemImage: String, identifier: String) -> some View {
        let isSelected = selection == tab
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(identifier)
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(14)
                .background(Color.accentColor, in: Circle())
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add transaction")
        .accessibilityHint("Opens quick add")
        .accessibilityIdentifier("addButton")
    }
}
