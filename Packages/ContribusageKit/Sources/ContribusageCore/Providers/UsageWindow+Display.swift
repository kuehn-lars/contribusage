import Foundation

/// How a window reads in the popover and the menu bar (SPEC §11.5, FR-11).
extension UsageWindow {
    /// FR-11: past its reset the value is unknown until the next refresh.
    public func isReset(at now: Date) -> Bool {
        resetsAt.map { $0 <= now } ?? false
    }

    /// "23%", "<1%", or "–" after a reset; the number in the locale's style (NFR-10).
    public func percentText(at now: Date, locale: Locale = .autoupdatingCurrent) -> String {
        let percent = IntegerFormatStyle<Int>.Percent(locale: locale)
        return isReset(at: now) ? "–" : isBelowOne ? "<" + percent.format(1) : percent.format(Int(usedPercent))
    }

    /// `nil` without a reset time; VoiceOver gets `.wide` units (§11.7).
    public func resetText(
        at now: Date, width: Duration.UnitsFormatStyle.UnitWidth = .condensedAbbreviated,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        if remaining <= 0 { return String(localized: "reset, refreshing…", bundle: .module, locale: locale) }  // US-2
        if remaining > 24 * 3600 {
            let time = resetsAt.formatted(.dateTime.weekday().hour().minute().locale(locale))
            return String(localized: "resets \(time)", bundle: .module, locale: locale)
        }
        let countdown = Duration.seconds(max(remaining, 60))  // never "0 min"
        let duration = countdown.formatted(.units(allowed: [.hours, .minutes], width: width).locale(locale))
        return String(localized: "resets in \(duration)", bundle: .module, locale: locale)
    }
}
