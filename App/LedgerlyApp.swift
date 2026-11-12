// LedgerlyApp.swift — app entry point. The root view (Views/RootView.swift) does the launch work.

import SwiftUI
import SwiftData

/// Extra launch arguments used only by the UI tests' screenshot tour.
enum UITestFlags {
    /// "-uiTestingDark": force Dark Mode.
    static var forceDark: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestingDark")
    }

    /// "-uiTestingDemoData": load the demo data set even under -uiTesting.
    static var loadDemoData: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestingDemoData")
    }
}

@main
struct LedgerlyApp: App {
    /// The one container shared with the App Intent. Touching it here opens the store before any view asks for data.
    private let container: ModelContainer = SharedModelContainer.shared

    init() {
        NotificationDelegate.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
        }
    }
}
