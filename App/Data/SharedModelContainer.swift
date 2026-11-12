// SharedModelContainer.swift — the one process-wide SwiftData container used by the app and the App Intent.

import Foundation
import SwiftData

enum SharedModelContainer {
    /// The container. On disk normally; in memory under `-uiTesting` or when the on-disk store can't be opened.
    static let shared: ModelContainer = bootstrap.container

    /// Non-nil when the on-disk store could not be opened and the app fell back to a temporary
    /// in-memory store. Show this to the user: anything they add will be lost when the app quits.
    static let startupError: String? = bootstrap.errorDescription

    /// True when data is not being written to disk (UI tests, or the fallback after an error).
    static let isInMemory: Bool = bootstrap.isInMemory

    private struct Bootstrap: Sendable {
        let container: ModelContainer
        let errorDescription: String?
        let isInMemory: Bool
    }

    private static let bootstrap: Bootstrap = makeBootstrap()

    private static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = LedgerSchema.schema
        let configuration = ModelConfiguration(
            "Ledgerly",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func makeBootstrap() -> Bootstrap {
        let wantsInMemory = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        if wantsInMemory {
            do {
                let container = try makeContainer(inMemory: true)
                return Bootstrap(container: container, errorDescription: nil, isInMemory: true)
            } catch {
                fatalError("Ledgerly could not create an in-memory data store: \(error)")
            }
        }
        do {
            let container = try makeContainer(inMemory: false)
            return Bootstrap(container: container, errorDescription: nil, isInMemory: false)
        } catch let diskError {
            let message = "Ledgerly couldn't open its saved data, so it is using temporary storage. "
                + "Anything you add now will be lost when the app closes. (\(diskError.localizedDescription))"
            do {
                let container = try makeContainer(inMemory: true)
                return Bootstrap(container: container, errorDescription: message, isInMemory: true)
            } catch {
                // Nothing can work without a store; stop loudly with both errors rather than limp along.
                fatalError("Ledgerly could not create any data store. Disk: \(diskError). Memory: \(error)")
            }
        }
    }
}
