import ContribusageCore
import UserNotifications

/// FR-13 to FR-15, FR-52: shows the planner's notes (SPEC §9.2), also while the popover makes the app active.
final class NotificationDelivery: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationDelivery()

    private let queue: AsyncStream<NotificationPlanner.Note>.Continuation

    private override init() {
        let (notes, queue) = AsyncStream.makeStream(of: NotificationPlanner.Note.self)
        self.queue = queue
        super.init()
        UNUserNotificationCenter.current().delegate = self
        // FR-52: one note at a time, 3 s apart, so macOS shows every banner instead of only the last.
        Task {
            for await note in notes {
                await Self.post(note)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Queues the notes in report order and returns at once, so a refresh never waits for the spacing.
    nonisolated func deliver(_ notes: [NotificationPlanner.Note]) {
        for note in notes { queue.yield(note) }
    }

    /// Asks for permission on the first note; there is no earlier prompt (ADR-029).
    private static func post(_ note: NotificationPlanner.Note) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = note.title
        // FR-52: Notification Center stacks a provider's notes.
        content.threadIdentifier = note.provider.rawValue
        try? await center.add(UNNotificationRequest(identifier: note.id, content: content, trigger: nil))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions { [.banner, .list] }
}
