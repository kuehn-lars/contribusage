import Foundation

/// What the Mac is doing, fed to the coordinator by the app (wake and sleep notifications, `NWPathMonitor`,
/// `ProcessInfo.isLowPowerModeEnabled`).
public struct ScheduleConditions: Sendable, Equatable {
    public var isOnline: Bool
    public var isLowPowerMode: Bool
    public var isAsleep: Bool
    public var lastWake: Date?

    public init(isOnline: Bool = true, isLowPowerMode: Bool = false, isAsleep: Bool = false, lastWake: Date? = nil) {
        self.isOnline = isOnline
        self.isLowPowerMode = isLowPowerMode
        self.isAsleep = isAsleep
        self.lastWake = lastWake
    }
}

/// The scheduling decision of SPEC §12 rule 7, provider neutral.
public enum Schedule {
    public static let wakeDelay: Duration = .seconds(10)

    /// When a polled source runs next, possibly in the past (it is due); `nil` while asleep or while offline for a source
    /// that needs the network. `manual` replaces interval and backoff by the policy's `manualFloor`. `triggers` are extra
    /// triggers' dates (popover opened, a window's reset), joined by the wake plus `wakeDelay`: the first one after the
    /// last run runs the source, but not within the minimum interval.
    public static func nextRun(
        policy: SchedulePolicy, lastSuccess: Date?, lastAttempt: Date?, failures: Int, now: Date,
        conditions: ScheduleConditions, manual: Bool = false, triggers: [Date] = []
    ) -> Date? {
        if conditions.isAsleep || (policy.needsNetwork && !conditions.isOnline) { return nil }
        let wake = conditions.lastWake.map { $0 + wakeDelay.timeInterval }
        var next = now
        if let last = [lastSuccess, lastAttempt].compactMap(\.self).max() {
            next =
                last
                + (manual ? policy.manualFloor : interval(policy, failures, lowPower: conditions.isLowPowerMode))
                .timeInterval
            if let trigger = (triggers + [wake].compactMap(\.self)).filter({ $0 > last }).min() {
                next = min(next, max(trigger, last + policy.minimumInterval.timeInterval))
            }
        }
        if let wake { next = max(next, wake) }
        return next
    }

    /// Clamped to the policy's bounds, 2×, 4×, 8× after failures up to the maximum, doubled in Low Power Mode.
    private static func interval(_ policy: SchedulePolicy, _ failures: Int, lowPower: Bool) -> Duration {
        var interval = min(max(policy.defaultInterval, policy.minimumInterval), policy.maximumInterval)
        interval = min(interval * (1 << min(failures, 3)), policy.maximumInterval)
        return lowPower ? interval * 2 : interval
    }
}

extension Duration {
    var timeInterval: TimeInterval { self / .seconds(1) }
}
