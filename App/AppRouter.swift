// AppRouter.swift — app-wide navigation state: selected tab, the add sheet, and where a tapped notification wants to go.

import Foundation
import Observation

/// The four real tabs. The centre (+) button is not a tab; it sets `AppRouter.isAddSheetPresented`.
enum AppTab: String, Hashable, Sendable, CaseIterable {
    case home
    case transactions
    case insights
    case settings
}

@MainActor
@Observable
final class AppRouter {
    /// A screen a notification can ask the app to open.
    enum Destination: String, Hashable, Sendable {
        /// The weekly earnings entry screen.
        case earnings
        /// The Needs Review inbox.
        case review
        /// The Transactions tab.
        case transactions
    }

    static let shared = AppRouter()

    /// Set when the user taps a notification. The root view shows the screen and then sets this back to nil.
    var pendingDestination: Destination?
    var selectedTab: AppTab = .home
    var isAddSheetPresented: Bool = false

    init() {}

    /// Asks the root view to show `destination`. Picks the matching tab right away and closes the add sheet.
    func open(_ destination: Destination) {
        isAddSheetPresented = false
        switch destination {
        case .earnings, .review:
            selectedTab = .home
        case .transactions:
            selectedTab = .transactions
        }
        pendingDestination = destination
    }
}
