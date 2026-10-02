import ContribusageCore
import UserNotifications

/// FR-13 to FR-15: shows the planner's notes (SPEC §9.2), also while the popover makes the app active.
final class NotificationDelivery: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationDelivery()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asks for permission on the first note; there is no earlier prompt (ADR-029).
    func deliver(_ notes: [NotificationPlanner.Note]) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
        for note in notes {
            let content = UNMutableNotificationContent()
            content.title = note.title
            try? await center.add(UNNotificationRequest(identifier: note.id, content: content, trigger: nil))
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions { [.banner, .list] }
}
