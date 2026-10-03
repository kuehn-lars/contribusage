import ContribusageCore
import Foundation
import Testing

/// SPEC §11.5 and FR-11: percent and reset text of a window.

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let enUS = Locale(identifier: "en_US")

private func window(percent: Double = 23, belowOne: Bool = false, resetsIn seconds: TimeInterval?) -> UsageWindow {
    UsageWindow(
        label: "Current session", kind: .session, usedPercent: percent, isBelowOne: belowOne,
        resetsAt: seconds.map { now + $0 })
}

@Test func percentTextIsUnknownOnceTheWindowHasReset() {
    #expect(window(resetsIn: 60).percentText(at: now, locale: enUS) == "23%")
    #expect(window(percent: 0, belowOne: true, resetsIn: 60).percentText(at: now, locale: enUS) == "<1%")
    #expect(window(resetsIn: nil).percentText(at: now, locale: enUS) == "23%")
    #expect(window(resetsIn: 0).percentText(at: now, locale: enUS) == "–")
    #expect(window(resetsIn: -60).isReset(at: now))
}

/// NFR-10: the number follows the locale ("23 %" in German, with a no-break space).
@Test func percentTextFollowsTheLocale() {
    #expect(window(resetsIn: 60).percentText(at: now, locale: Locale(identifier: "de_DE")) == "23\u{a0}%")
}

@Test func resetTextFollowsTheFormattingRules() {
    func text(_ seconds: TimeInterval?, _ width: Duration.UnitsFormatStyle.UnitWidth = .condensedAbbreviated) -> String?
    {
        window(resetsIn: seconds).resetText(at: now, width: width, locale: enUS)
    }
    #expect(text(nil) == nil)
    #expect(text(-1) == "reset, refreshing…")
    #expect(text(20) == "resets in 1 min")
    #expect(text(12 * 60) == "resets in 12 min")
    #expect(text(2 * 3600 + 10 * 60) == "resets in 2 hr 10 min")
    #expect(text(2 * 3600 + 10 * 60, .wide) == "resets in 2 hours, 10 minutes")
    #expect(text(25 * 3600)?.hasPrefix("resets ") == true)
    #expect(text(25 * 3600)?.contains(" in ") == false)
}
