import Foundation

/// FR-13 to FR-15: the notifications a fetched limits report brings. Pure; the app delivers them (SPEC §9.2).
public enum NotificationPlanner {
    /// FR-15: what was sent in one window's reset cycle. The highest threshold stands for every lower one.
    public struct Cycle: Equatable, Sendable, Codable {
        public internal(set) var resetsAt: Date?
        public let threshold: Int
        /// When `threshold` was sent; FR-15 prunes the cycle 8 days later.
        public let sentAt: Date
    }

    /// The cycles by provider and window label, as `state.json` stores them.
    public typealias Sent = [ProviderID: [String: Cycle]]

    public struct Note: Equatable, Sendable {
        /// One per window and reset cycle, so a later note replaces an earlier one in Notification Center.
        public let id: String
        /// FR-52: the notification thread, so Notification Center stacks a provider's notes.
        public let provider: ProviderID
        /// Starts with the provider's display name (SPEC §7.7).
        public let title: String

        fileprivate init(_ provider: ProviderID, _ label: String, _ resetsAt: Date?, title: String) {
            id = "\(provider.rawValue)|\(label)|\(resetsAt?.timeIntervalSince1970.description ?? "-")"
            self.provider = provider
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
            // US-3, FR-15: the printed reset time drifts by a minute between refreshes (P-7), so only a move of more
            // than 1 h ends the cycle and re-arms the thresholds. A window printed without a reset time ends it once
            // the cycle's own time has passed; a cycle without one is kept (ADR-038).
            if let ended = cycle, let was = ended.resetsAt,
                window.resetsAt.map({ abs($0.timeIntervalSince(was)) > 3600 }) ?? (now > was)
            {
                if settings.notifyOnReset {
                    notes.append(
                        Note(
                            report.provider, window.label, was,
                            title: String(localized: "\(displayName): \(title) has reset", bundle: .module)))
                }
                cycle = nil
            }
            // The cycle keeps its first known reset time, so its notes share one identifier (FR-52).
            let resetsAt = cycle?.resetsAt ?? window.resetsAt
            let floor = cycle?.threshold ?? 0
            // FR-13: only the highest threshold crossed in this refresh.
            if let highest = thresholds.last(where: { window.usedPercent >= Double($0) && $0 > floor }) {
                cycle = Cycle(resetsAt: resetsAt, threshold: highest, sentAt: now)
                notes.append(
                    Note(
                        report.provider, window.label, resetsAt,
                        title: String(localized: "\(displayName): \(title) at \(highest) %", bundle: .module)))
            } else {
                cycle?.resetsAt = resetsAt
            }
            cycles[window.label] = cycle
        }
        sent[report.provider] = cycles.isEmpty ? nil : cycles
        return notes
    }
}
