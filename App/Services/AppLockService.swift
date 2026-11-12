// AppLockService.swift — optional Face ID / passcode app lock, and the lock screen shown while locked.

import Foundation
import LocalAuthentication
import Observation
import SwiftUI

@MainActor
@Observable
final class AppLockService {
    static let shared = AppLockService()

    /// True while the lock screen should cover the app.
    private(set) var isLocked: Bool = false
    /// True while the system authentication prompt is up.
    private(set) var isAuthenticating: Bool = false
    /// Why the last unlock attempt failed, or nil. Shown on the lock screen.
    private(set) var lastErrorMessage: String?

    private enum AuthOutcome: Sendable {
        case success
        /// The device has no passcode or biometrics set up, so there is nothing to authenticate with.
        case unavailable
        case failed(String)
    }

    init() {
        isLocked = AppLockService.lockIsActive
    }

    /// Whether the lock is switched on (always off under `-uiTesting`).
    private static var lockIsActive: Bool {
        AppSettings.shared.faceIDLockEnabled && !LaunchFlags.isUITesting
    }

    /// Whether this device can authenticate at all (Face ID, Touch ID or a passcode).
    /// Settings uses this to decide whether the lock toggle can be turned on.
    static func canAuthenticate() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// Locks the app if the user turned the lock on. Call when the app goes to the background.
    func lockIfEnabled() {
        guard AppLockService.lockIsActive else { return }
        // Don't re-lock underneath the system prompt (it briefly makes the scene inactive).
        guard !isAuthenticating else { return }
        lastErrorMessage = nil
        isLocked = true
    }

    /// Shows the Face ID / passcode prompt and unlocks on success. Safe to call when already unlocked.
    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        let outcome = await AppLockService.authenticate(reason: "Unlock Ledgerly to see your spending.")
        isAuthenticating = false
        switch outcome {
        case .success:
            lastErrorMessage = nil
            isLocked = false
        case .unavailable:
            // No passcode on the device: let the user in rather than lock them out of their own data.
            lastErrorMessage = nil
            isLocked = false
        case .failed(let message):
            lastErrorMessage = message
        }
    }

    /// Runs entirely off the main actor so the non-Sendable LAContext never crosses an actor boundary.
    private nonisolated static func authenticate(reason: String) async -> AuthOutcome {
        let context = LAContext()
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availabilityError) else {
            return .unavailable
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            return success ? .success : .failed("Couldn't confirm it's you. Try again.")
        } catch {
            return .failed("Couldn't confirm it's you. Try again.")
        }
    }
}

/// Full-screen cover shown while the app is locked.
struct LockScreenView: View {
    let lock: AppLockService

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Ledgerly")
                .font(.largeTitle)
                .bold()
                .accessibilityAddTraits(.isHeader)
            Text("Locked")
                .font(.title3)
                .foregroundStyle(.secondary)
            if let message = lock.lastErrorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                Task { await lock.unlock() }
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(lock.isAuthenticating)
            .accessibilityLabel("Unlock Ledgerly")
            .accessibilityHint("Uses Face ID or your passcode")
            .accessibilityIdentifier("lock.unlockButton")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task {
            await lock.unlock()
        }
    }
}
