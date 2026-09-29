import Foundation

/// How a window reads in the popover and the menu bar (SPEC §11.5, FR-11).
extension UsageWindow {
    /// FR-11: past its reset the value is unknown until the next refresh.
    public func isReset(at now: Date) -> Bool {
        resetsAt.map { $0 <= now } ?? false
    }

    /// "23%", "<1%", or "–" after a reset.
    public func percentText(at now: Date) -> String {
        isReset(at: now) ? "–" : isBelowOne ? "<1%" : "\(Int(usedPercent))%"
    }

    /// `nil` without a reset time; VoiceOver gets `.wide` units (§11.7).
    public func resetText(
        at now: Date, width: Duration.UnitsFormatStyle.UnitWidth = .condensedAbbreviated,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        if remaining <= 0 { return "reset, refreshing…" }  // US-2
        if remaining > 24 * 3600 {
            return "resets \(resetsAt.formatted(.dateTime.weekday().hour().minute().locale(locale)))"
        }
        let countdown = Duration.seconds(max(remaining, 60))  // never "0 min"
        return "resets in \(countdown.formatted(.units(allowed: [.hours, .minutes], width: width).locale(locale)))"
    }
}
