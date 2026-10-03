import ContribusageCore
import Foundation
import Testing

/// FR-13 to FR-15, US-3, SPEC §16.3: thresholds fire once per provider, window and reset cycle, and re-arm after reset.

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let cycle = now.addingTimeInterval(3600)
private let a = ProviderID(rawValue: "a")
private let b = ProviderID(rawValue: "b")

private func report(_ percent: Double, _ id: ProviderID = a, resetsAt: Date? = cycle) -> LimitsReport {
    LimitsReport(
        provider: id,
        windows: [
            UsageWindow(
                label: "Current session", kind: .session, usedPercent: percent, isBelowOne: false, resetsAt: resetsAt)
        ],
        billingNote: nil, insights: nil, rawOutput: nil)
}

private func titles(
    _ report: LimitsReport, _ sent: inout NotificationPlanner.Sent,
    settings: NotificationPlanner.Settings = .init(), at time: Date = now
) -> [String] {
    NotificationPlanner.plan(
        report, displayName: "Claude Code", windowTitle: { $0 }, settings: settings, sent: &sent, now: time
    ).map(
        \.title)
}

@Test func eachThresholdFiresOncePerCycle() {
    var sent: NotificationPlanner.Sent = [:]
    #expect(titles(report(79), &sent).isEmpty)
    #expect(titles(report(80), &sent) == ["Claude Code: Current session at 80 %"])
    #expect(titles(report(85), &sent).isEmpty)
    #expect(titles(report(96), &sent) == ["Claude Code: Current session at 95 %"])
    #expect(titles(report(99), &sent).isEmpty)
    // FR-15: the cycle's highest threshold stands for every lower one, also one added mid-cycle.
    #expect(titles(report(99), &sent, settings: .init(thresholds: [90, 95])).isEmpty)
}

/// Both crossings are sent under the window's one identifier, so Notification Center keeps only the 95 % one.
@Test func aJumpOverTwoThresholdsSendsBothUnderOneIdentifier() {
    var sent: NotificationPlanner.Sent = [:]
    let notes = NotificationPlanner.plan(
        report(97), displayName: "Claude Code", windowTitle: { $0 }, settings: .init(), sent: &sent, now: now)
    #expect(notes.map(\.title) == ["Claude Code: Current session at 80 %", "Claude Code: Current session at 95 %"])
    #expect(Set(notes.map(\.id)).count == 1)
}

@Test func aResetReArmsAndNotifiesOnlyWhenAsked() {
    var sent: NotificationPlanner.Sent = [:]
    _ = titles(report(90), &sent)
    let next = cycle.addingTimeInterval(5 * 3600)
    #expect(titles(report(10, resetsAt: next), &sent, at: cycle).isEmpty)
    #expect(titles(report(81, resetsAt: next), &sent, at: cycle) == ["Claude Code: Current session at 80 %"])

    var asked: NotificationPlanner.Sent = [:]
    let onReset = NotificationPlanner.Settings(notifyOnReset: true)
    _ = titles(report(90), &asked, settings: onReset)
    #expect(
        titles(report(10, resetsAt: next), &asked, settings: onReset, at: cycle) == [
            "Claude Code: Current session has reset"
        ])
    #expect(titles(report(10, resetsAt: next), &asked, settings: onReset, at: cycle).isEmpty)
}

@Test func identicalLabelsFromTwoProvidersAreSeparate() {
    var sent: NotificationPlanner.Sent = [:]
    #expect(titles(report(85, a), &sent).count == 1)
    #expect(titles(report(85, b), &sent).count == 1)
}

/// FR-13: up to 3 values between 50 and 99; anything else in the defaults is ignored.
@Test func thresholdsOutsideTheRangeAreIgnored() {
    var sent: NotificationPlanner.Sent = [:]
    let settings = NotificationPlanner.Settings(thresholds: [10, 100, 60, 60, 70, 75, 90])
    #expect(titles(report(100), &sent, settings: settings).map { $0.suffix(4) } == ["60 %", "70 %", "75 %"])
}

/// FR-15: keys older than 8 days are pruned; a window past its reset waits for the next refresh (FR-11).
@Test func oldKeysArePrunedAndResetWindowsWait() {
    var sent: NotificationPlanner.Sent = [:]
    _ = titles(report(85, resetsAt: nil), &sent)
    #expect(titles(report(85, resetsAt: nil), &sent, at: now.addingTimeInterval(8 * 86400)).isEmpty)
    #expect(titles(report(85, resetsAt: nil), &sent, at: now.addingTimeInterval(8 * 86400 + 1)).count == 1)

    var passed: NotificationPlanner.Sent = [:]
    #expect(titles(report(85, resetsAt: now), &passed).isEmpty)
}

/// NFR-10: the title shows the provider's window title; the cycle stays keyed by the label as printed.
@Test func titlesUseTheWindowTitleAndKeysTheLabel() {
    var sent: NotificationPlanner.Sent = [:]
    let notes = NotificationPlanner.plan(
        report(80), displayName: "Claude Code", windowTitle: { $0 == "Current session" ? "Aktuelle Sitzung" : $0 },
        settings: .init(), sent: &sent, now: now)
    #expect(notes.map(\.title) == ["Claude Code: Aktuelle Sitzung at 80 %"])
    #expect(sent[a]?.keys.first == "Current session")
}
