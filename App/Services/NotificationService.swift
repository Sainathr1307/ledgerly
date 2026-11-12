// NotificationService.swift — local notifications: the Monday earnings reminder, "transaction logged" banners, and tap routing.

import Foundation
import UserNotifications

enum NotificationService {
    /// Fixed identifier of the Monday reminder, so scheduling again replaces the old one.
    static let weeklyEarningsReminderIdentifier = "ledgerly.weeklyEarningsReminder"

    /// Key in a notification's userInfo whose value is an `AppRouter.Destination` raw value.
    static let destinationKey = "destination"

    // MARK: - Permission

    /// Asks for permission to show alerts, sounds and badges. Returns whether it was granted.
    /// Never throws. Under `-uiTesting` it returns false without showing the system prompt.
    static func requestAuthorization() async -> Bool {
        if LaunchFlags.isUITesting { return false }
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// The current permission state.
    static func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    /// True when the app is allowed to deliver notifications.
    static func isAuthorized() async -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Monday earnings reminder

    /// Schedules (or replaces) the repeating reminder for every Monday at `hour:minute` local time.
    /// The trigger is a calendar match, so the system keeps it at the same wall-clock time across
    /// daylight-saving and time-zone changes. Returns false and does nothing when permission is missing.
    @discardableResult
    static func scheduleWeeklyEarningsReminder(hour: Int, minute: Int) async -> Bool {
        guard await isAuthorized() else { return false }

        let content = UNMutableNotificationContent()
        content.title = "New week!"
        content.body = "What did you earn last week?"
        content.sound = .default
        content.userInfo = [destinationKey: "earnings"]

        var components = DateComponents()
        components.weekday = 2 // 1 = Sunday, 2 = Monday in the Gregorian calendar
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: weeklyEarningsReminderIdentifier,
            content: content,
            trigger: trigger
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    /// Removes the Monday reminder, pending or already delivered.
    static func cancelWeeklyEarningsReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [weeklyEarningsReminderIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [weeklyEarningsReminderIdentifier])
    }

    /// A line for Settings such as "Every Monday at 8:00 AM", or nil when no reminder is scheduled.
    static func pendingReminderDescription() async -> String? {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        for request in requests where request.identifier == weeklyEarningsReminderIdentifier {
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { continue }
            let hour = trigger.dateComponents.hour ?? 8
            let minute = trigger.dateComponents.minute ?? 0
            return "Every Monday at " + timeText(hour: hour, minute: minute)
        }
        return nil
    }

    // MARK: - Transaction logged

    /// Posts an immediate local notification for a transaction saved by the App Intent.
    /// Tapping it opens Needs Review when `needsReview` is true, otherwise the Transactions tab.
    /// Returns false and does nothing when permission is missing.
    @discardableResult
    static func postTransactionLogged(title: String, body: String, needsReview: Bool) async -> Bool {
        guard await isAuthorized() else { return false }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [destinationKey: needsReview ? "review" : "transactions"]

        let request = UNNotificationRequest(
            identifier: "ledgerly.transactionLogged." + UUID().uuidString,
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private

    /// "8:00 AM" / "08:00" in the user's locale.
    private static func timeText(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        guard let date = Calendar.current.date(from: components) else {
            let minuteText = minute < 10 ? "0\(minute)" : "\(minute)"
            return "\(hour):\(minuteText)"
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Shows banners while the app is open and turns a notification tap into an `AppRouter` destination.
/// Call `NotificationDelegate.install()` once at launch (in the App's init), before the first scene appears.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationDelegate()

    /// Makes this the notification centre's delegate. The centre holds it weakly; `shared` keeps it alive.
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    // The system calls these off the main actor, so the class is deliberately not @MainActor.

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Pull the plain String out before changing actors; UNNotificationResponse isn't Sendable.
        let userInfo = response.notification.request.content.userInfo
        guard let raw = userInfo[NotificationService.destinationKey] as? String,
              let destination = AppRouter.Destination(rawValue: raw) else {
            return
        }
        await MainActor.run {
            AppRouter.shared.open(destination)
        }
    }
}
