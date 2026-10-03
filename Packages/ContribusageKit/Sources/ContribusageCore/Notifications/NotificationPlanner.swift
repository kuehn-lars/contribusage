import Foundation

/// FR-13 to FR-15: the notifications a fetched limits report brings. Pure; the app delivers them (SPEC §9.2).
public enum NotificationPlanner {
    /// FR-15: what was sent in one window's reset cycle. The highest threshold stands for every lower one.
    public struct Cycle: Equatable, Sendable, Codable {
        public let resetsAt: Date?
        public let threshold: Int
        /// When `threshold` was sent; FR-15 prunes the cycle 8 days later.
        public let sentAt: Date
    }

    /// The cycles by provider and window label, as `state.json` stores them.
    public typealias Sent = [ProviderID: [String: Cycle]]

    public struct Note: Equatable, Sendable {
        /// One per window and reset cycle, so a later note replaces an earlier one in Notification Center.
        public let id: String
        /// Starts with the provider's display name (SPEC §7.7).
        public let title: String

        fileprivate init(_ provider: ProviderID, _ label: String, _ resetsAt: Date?, title: String) {
            id = "\(provider.rawValue)|\(label)|\(resetsAt?.timeIntervalSince1970.description ?? "-")"
            self.title = title
        }
    }

    /// `notificationThresholds` and `notifyOnReset` (SPEC §10.7).
    public struct Settings: Sendable {
        public var thresholds: [Int]
        public var notifyOnReset: Bool

        public init(thresholds: [Int] = [80, 95], notifyOnReset: Bool = false) {
            self.thresholds = thresholds
            self.notifyOnReset = notifyOnReset
        }
    }

    /// Updates `sent` with the report's windows and drops cycles sent more than 8 days ago.
    public static func plan(
        _ report: LimitsReport, displayName: String, windowTitle: (String) -> String, settings: Settings,
        sent: inout Sent, now: Date
    ) -> [Note] {
        // FR-13: up to 3 values between 50 and 99; the defaults can hold anything.
        let thresholds = Set(settings.thresholds.filter { (50...99).contains($0) }).sorted().prefix(3)
        sent = sent.compactMapValues { cycles in
            let kept = cycles.filter { now.timeIntervalSince($0.value.sentAt) <= 8 * 86400 }
            return kept.isEmpty ? nil : kept
        }
        var cycles = sent[report.provider] ?? [:]
        var notes: [Note] = []
        // FR-11: a window past its reset is unknown until the next refresh.
        for window in report.windows where !window.isReset(at: now) {
            let title = windowTitle(window.label)
            var cycle = cycles[window.label]
            // US-3: another reset time means the cycle ended, so the thresholds re-arm.
            if let ended = cycle, ended.resetsAt != window.resetsAt {
                if settings.notifyOnReset {
                    notes.append(
                        Note(
                            report.provider, window.label, ended.resetsAt,
                            title: String(localized: "\(displayName): \(title) has reset", bundle: .module)))
                }
                cycle = nil
            }
            let crossed = thresholds.filter { window.usedPercent >= Double($0) && $0 > cycle?.threshold ?? 0 }
            if let highest = crossed.last { cycle = Cycle(resetsAt: window.resetsAt, threshold: highest, sentAt: now) }
            cycles[window.label] = cycle
            notes += crossed.map {
                Note(
                    report.provider, window.label, window.resetsAt,
                    title: String(localized: "\(displayName): \(title) at \($0) %", bundle: .module))
            }
        }
        sent[report.provider] = cycles.isEmpty ? nil : cycles
        return notes
    }
}
