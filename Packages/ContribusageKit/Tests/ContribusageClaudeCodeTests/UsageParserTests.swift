import ContribusageClaudeCode
import ContribusageCore
import Foundation
import Testing

private func utc(_ iso: String) -> Date {
    try! Date(iso, strategy: .iso8601)
}

private func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures/usage"))
    return try String(contentsOf: url, encoding: .utf8)
}

private func parse(_ output: String, now: Date, fallbackZone: TimeZone = .current) -> [UsageWindow] {
    UsageParser.report(from: output, now: now, fallbackZone: fallbackZone).windows
}

/// Appendix A: the expected parse with `now` = 2026-09-27 20:00 UTC.
@Test func parsesSubscriptionBaseline() throws {
    let windows = parse(try fixture("subscription-basic"), now: utc("2026-09-27T20:00:00Z"))
    #expect(
        windows == [
            .init(
                label: "Current session", kind: .session, usedPercent: 3, isBelowOne: false,
                resetsAt: utc("2026-09-28T02:09:00Z")),
            .init(
                label: "Current week (all models)", kind: .weekly, usedPercent: 5, isBelowOne: false,
                resetsAt: utc("2026-10-04T16:59:00Z")),
        ])
}

/// P-1: color codes around and inside lines change nothing.
@Test func stripsANSI() throws {
    let plain = try fixture("subscription-basic")
    let colored = plain.split(separator: "\n", omittingEmptySubsequences: false)
        .map { "\u{1B}[1;32m\($0.replacingOccurrences(of: ":", with: "\u{1B}[0m:"))\u{1B}[0m" }
        .joined(separator: "\n")
    let now = utc("2026-09-27T20:00:00Z")
    #expect(parse(colored, now: now) == parse(plain, now: now))
}

/// P-5: "<1%" is 0.5 with the flag set.
@Test func parsesBelowOne() {
    let windows = parse("Current session: <1% used", now: .now)
    #expect(
        windows == [.init(label: "Current session", kind: .session, usedPercent: 0.5, isBelowOne: true, resetsAt: nil)])
}

/// P-6 to P-9, with SPEC §16.3's DST and New Year cases. The fallback zone is UTC.
@Test(arguments: [
    // P-7 formats in order; P-8 time only resolves to the next occurrence after now.
    ("resets Sep 28 at 4:09am (Europe/Berlin)", "2026-09-27T20:00:00Z", "2026-09-28T02:09:00Z"),
    ("resets Sep 28 at 4am (Europe/Berlin)", "2026-09-27T20:00:00Z", "2026-09-28T02:00:00Z"),
    ("resets Sep 28 (Europe/Berlin)", "2026-09-27T20:00:00Z", "2026-09-27T22:00:00Z"),
    ("resets 4:09am (Europe/Berlin)", "2026-09-27T20:00:00Z", "2026-09-28T02:09:00Z"),
    ("resets 11pm (Europe/Berlin)", "2026-09-27T20:00:00Z", "2026-09-27T21:00:00Z"),
    // P-8: within 24 h in the past stays this year, older rolls to next year.
    ("resets Sep 27 at 4am (Europe/Berlin)", "2026-09-27T20:00:00Z", "2026-09-27T02:00:00Z"),
    ("resets Sep 25 at 4am (Europe/Berlin)", "2026-09-27T20:00:00Z", "2027-09-25T02:00:00Z"),
    // Across the Berlin DST change on 2026-10-25 (CEST to CET) and across New Year.
    ("resets Oct 26 at 4:09am (Europe/Berlin)", "2026-10-20T12:00:00Z", "2026-10-26T03:09:00Z"),
    ("resets 4:09am (Europe/Berlin)", "2026-10-24T12:00:00Z", "2026-10-25T03:09:00Z"),
    ("resets Jan 2 at 6:59pm (Europe/Berlin)", "2026-12-30T12:00:00Z", "2027-01-02T17:59:00Z"),
    // P-6: unknown or missing zone falls back to the Mac's zone.
    ("resets Sep 28 at 4:09am (Mars/Olympus)", "2026-09-27T20:00:00Z", "2026-09-28T04:09:00Z"),
    ("resets Sep 28 at 4:09 AM", "2026-09-27T20:00:00Z", "2026-09-28T04:09:00Z"),
])
func resolvesResetTime(clause: String, now: String, expected: String) {
    let windows = parse("Current session: 3% used · \(clause)", now: utc(now), fallbackZone: .gmt)
    #expect(windows.first?.resetsAt == utc(expected))
}

/// P-9: an unreadable or missing reset clause keeps the window.
@Test(arguments: [
    "Current week (all models): 42.5% used · resets whenever",
    "Current week (all models): 42.5% used",
])
func keepsWindowWithoutResetTime(line: String) {
    let windows = parse(line, now: .now)
    let expected = UsageWindow(
        label: "Current week (all models)", kind: .weekly, usedPercent: 42.5, isBelowOne: false, resetsAt: nil)
    #expect(windows == [expected])
}

/// SPEC §8.1.4: model specific weeks are weekly, unknown labels stay as `other`.
@Test(arguments: [
    ("Current session", WindowKind.session),
    ("Current week (all models)", .weekly),
    ("Current week (<model>)", .weekly),
    ("Extra usage", .other),
])
func classifiesWindow(label: String, kind: WindowKind) {
    #expect(parse("\(label): 42% used", now: .now).map(\.kind) == [kind])
}

/// P-3: lines that only look similar are not windows.
@Test func ignoresNonWindowLines() {
    let text = """
        Top skills: /skill-a 76%, /skill-b 9%
          80% of your usage was at >150k context
        Last 24h · 668 requests
        """
    #expect(parse(text, now: .now).isEmpty)
}

/// P-10, P-11: the billing line, the insights block by period, the untouched output.
@Test func buildsSubscriptionReport() throws {
    let output = try fixture("subscription-basic")
    let now = utc("2026-09-27T20:00:00Z")
    let report = UsageParser.report(from: "\u{1B}[1m\(output)", now: now)
    #expect(report.provider == .claudeCode)
    #expect(report.windows == parse(output, now: now))
    #expect(report.billingNote == "You are currently using your subscription to power your Claude Code usage")
    #expect(report.rawOutput == "\u{1B}[1m\(output)")

    typealias Share = Insights.Share
    let insights = try #require(report.insights)
    #expect(insights.note?.hasPrefix("Approximate, based on local sessions on this machine;") == true)
    #expect(insights.periods.map(\.label) == ["Last 24h", "Last 7d"])
    #expect(insights.periods.map(\.summary) == ["668 requests · 8 sessions", "3002 requests · 63 sessions"])
    let week = insights.periods[1]
    #expect(
        week.shares == [
            Share(label: "At >150k context", percent: 72), Share(label: "Sessions active for 8+ hours", percent: 13),
            Share(label: "Subagent-heavy sessions", percent: 12),
        ])
    #expect(week.rankings.map(\.title) == ["Skills", "Subagents", "Plugins"])
    #expect(
        week.rankings[0].items.prefix(2) == [
            Share(label: "/skill-a", percent: 29), Share(label: "/skill-d", percent: 18),
        ])
    #expect(week.rankings[2].items == [Share(label: "plugin-a", percent: 29)])
}

/// P-11: lines that fit no rule are kept without a percent, never dropped; a block without a period is no insights.
@Test func keepsUnknownInsightLines() throws {
    let output = """
        What's contributing to your limits usage?
        Last 24h · 5 requests
          Mostly one project
          Top models: model-a <1%
        """
    let period = try #require(UsageParser.report(from: output, now: .now).insights?.periods.first)
    #expect(period.shares == [Insights.Share(label: "Mostly one project", percent: nil)])
    #expect(
        period.rankings == [
            Insights.Ranking(title: "Models", items: [Insights.Share(label: "model-a <1%", percent: nil)])
        ])
    #expect(UsageParser.report(from: "What's contributing to your limits usage?\nA note\n", now: .now).insights == nil)
}

/// R-2 (Claude Code 2.1.284): API key billing and logged out both print the same cost summary, exit 0.
@Test(arguments: ["not-subscription", "logged-out"])
func buildsReportWithoutSubscription(name: String) throws {
    let report = UsageParser.report(from: try fixture(name), now: .now)
    #expect(report.windows.isEmpty)
    #expect(report.billingNote == "Total cost:            $0.0000")
    #expect(report.insights == nil)
}
