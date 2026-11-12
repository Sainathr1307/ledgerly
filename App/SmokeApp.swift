// Temporary entry point used only on the ci/smoke branch to compile the data layer.
import SwiftUI
import LedgerlyCore

@main
struct SmokeApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Ledgerly smoke build")
                .task {
                    try? await LedgerRepository.shared.seedDefaultCategoriesIfNeeded()
                    let data = await LedgerRepository.shared.snapshotAll()
                    print(data.categories.count)
                }
        }
    }
}
