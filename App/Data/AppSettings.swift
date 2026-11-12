// AppSettings.swift — small UserDefaults-backed settings store, plus the UI-test launch flags.

import Foundation
import Observation

/// Launch arguments the UI tests pass to put the app in a known state.
enum LaunchFlags {
    /// UserDefaults suite used instead of `.standard` under `-uiTesting`. Wiped at every launch.
    static let uiTestingDefaultsSuite = "uitests"

    /// `-uiTesting`: in-memory store, clean settings, onboarding skipped, no notification prompt, lock off.
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    /// `-uiTestingGoalPrompt`: show the monthly goal sheet on launch.
    static var forceGoalPrompt: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestingGoalPrompt")
    }

    /// `-uiTestingSeedReview`: insert one zero-amount, blank-merchant wallet transaction on launch.
    static var seedReviewItem: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestingSeedReview")
    }
}

/// UserDefaults keys. File-level so both main-actor and nonisolated code can use them.
private enum SettingsKey {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let lastGoalPromptMonth = "lastGoalPromptMonth"
    static let reminderHour = "reminderHour"
    static let reminderMinute = "reminderMinute"
    static let faceIDLockEnabled = "faceIDLockEnabled"
    static let financeKitEnabled = "financeKitEnabled"
    static let currencyCode = "currencyCode"
    static let demoDataLoaded = "demoDataLoaded"
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored
    private let defaults: UserDefaults

    private init() {
        let store = AppSettings.makeStore()
        if LaunchFlags.isUITesting {
            // Start every UI-test run from a clean slate, with onboarding out of the way.
            store.removePersistentDomain(forName: LaunchFlags.uiTestingDefaultsSuite)
            store.set(true, forKey: SettingsKey.hasCompletedOnboarding)
        }
        store.register(defaults: [
            SettingsKey.reminderHour: 8,
            SettingsKey.reminderMinute: 0,
            SettingsKey.currencyCode: "USD"
        ])
        defaults = store
    }

    /// The backing store: `.standard`, or the throwaway "uitests" suite under `-uiTesting`.
    private nonisolated static func makeStore() -> UserDefaults {
        if LaunchFlags.isUITesting, let suite = UserDefaults(suiteName: LaunchFlags.uiTestingDefaultsSuite) {
            return suite
        }
        return UserDefaults.standard
    }

    /// The saved currency code, readable from any thread (the App Intent uses this). Defaults to "USD".
    nonisolated static var storedCurrencyCode: String {
        makeStore().string(forKey: SettingsKey.currencyCode) ?? "USD"
    }

    // Each property reads and writes UserDefaults directly and reports the access to Observation
    // by hand, so SwiftUI views that read a setting update when it changes.

    var hasCompletedOnboarding: Bool {
        get {
            access(keyPath: \.hasCompletedOnboarding)
            return defaults.bool(forKey: SettingsKey.hasCompletedOnboarding)
        }
        set {
            withMutation(keyPath: \.hasCompletedOnboarding) {
                defaults.set(newValue, forKey: SettingsKey.hasCompletedOnboarding)
            }
        }
    }

    /// "yyyy-MM" of the month the goal sheet was last shown for, or nil if never shown.
    var lastGoalPromptMonth: String? {
        get {
            access(keyPath: \.lastGoalPromptMonth)
            return defaults.string(forKey: SettingsKey.lastGoalPromptMonth)
        }
        set {
            withMutation(keyPath: \.lastGoalPromptMonth) {
                if let newValue {
                    defaults.set(newValue, forKey: SettingsKey.lastGoalPromptMonth)
                } else {
                    defaults.removeObject(forKey: SettingsKey.lastGoalPromptMonth)
                }
            }
        }
    }

    /// Hour (0–23) of the Monday earnings reminder. Default 8.
    var reminderHour: Int {
        get {
            access(keyPath: \.reminderHour)
            return defaults.integer(forKey: SettingsKey.reminderHour)
        }
        set {
            withMutation(keyPath: \.reminderHour) {
                defaults.set(min(max(newValue, 0), 23), forKey: SettingsKey.reminderHour)
            }
        }
    }

    /// Minute (0–59) of the Monday earnings reminder. Default 0.
    var reminderMinute: Int {
        get {
            access(keyPath: \.reminderMinute)
            return defaults.integer(forKey: SettingsKey.reminderMinute)
        }
        set {
            withMutation(keyPath: \.reminderMinute) {
                defaults.set(min(max(newValue, 0), 59), forKey: SettingsKey.reminderMinute)
            }
        }
    }

    var faceIDLockEnabled: Bool {
        get {
            access(keyPath: \.faceIDLockEnabled)
            return defaults.bool(forKey: SettingsKey.faceIDLockEnabled)
        }
        set {
            withMutation(keyPath: \.faceIDLockEnabled) {
                defaults.set(newValue, forKey: SettingsKey.faceIDLockEnabled)
            }
        }
    }

    /// User toggle for the optional FinanceKit source. Default false. Only meaningful in builds
    /// compiled with FINANCEKIT_ENABLED.
    var financeKitEnabled: Bool {
        get {
            access(keyPath: \.financeKitEnabled)
            return defaults.bool(forKey: SettingsKey.financeKitEnabled)
        }
        set {
            withMutation(keyPath: \.financeKitEnabled) {
                defaults.set(newValue, forKey: SettingsKey.financeKitEnabled)
            }
        }
    }

    /// ISO 4217 code used for new transactions and for display. Default "USD".
    var currencyCode: String {
        get {
            access(keyPath: \.currencyCode)
            return defaults.string(forKey: SettingsKey.currencyCode) ?? "USD"
        }
        set {
            withMutation(keyPath: \.currencyCode) {
                defaults.set(newValue, forKey: SettingsKey.currencyCode)
            }
        }
    }

    /// True once the DEBUG demo data has been inserted, so it isn't inserted twice.
    var demoDataLoaded: Bool {
        get {
            access(keyPath: \.demoDataLoaded)
            return defaults.bool(forKey: SettingsKey.demoDataLoaded)
        }
        set {
            withMutation(keyPath: \.demoDataLoaded) {
                defaults.set(newValue, forKey: SettingsKey.demoDataLoaded)
            }
        }
    }

    /// Puts every setting back to its default (used by "Erase all data").
    func resetAll() {
        hasCompletedOnboarding = false
        lastGoalPromptMonth = nil
        reminderHour = 8
        reminderMinute = 0
        faceIDLockEnabled = false
        financeKitEnabled = false
        currencyCode = "USD"
        demoDataLoaded = false
    }
}
