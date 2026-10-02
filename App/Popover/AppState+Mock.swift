import ContribusageClaudeCode
import ContribusageCore
import ContribusageGitHub
import SwiftUI

/// Mock data for the previews; the running app uses `AppState.live()`.
extension AppState {
    static func mock(
        limits: SourceState<LimitsReport> = .loaded(.fresh(.mockLimits)),
        activity: SourceState<ActivityReport> = .loaded(.fresh(.mockActivity)),
        github: SourceState<GitHubReport> = .loaded(.fresh(.mockGitHub)),
        secondProvider: Bool = false
    ) -> AppState {
        var providers = [ProviderGroupState(descriptor: .mockClaudeCode, limits: limits, activity: activity)]
        if secondProvider {
            // A limits-only provider, to show that groups follow capabilities.
            providers.append(ProviderGroupState(descriptor: .mockOther, limits: .loaded(.fresh(.mockOtherLimits))))
        }
        return AppState(providers: providers, github: github)
    }
}

extension Snapshot {
    static func fresh(_ value: Value) -> Snapshot {
        Snapshot(value: value, fetchedAt: .now.addingTimeInterval(-120), origin: .cache)
    }
    static func old(_ value: Value) -> Snapshot {
        Snapshot(value: value, fetchedAt: .now.addingTimeInterval(-3 * 3600), origin: .cache)
    }
}

extension ProviderDescriptor {
    static let mockClaudeCode = ProviderDescriptor(
        id: .claudeCode, displayName: "Claude Code", symbolName: "sparkle",
        capabilities: [.limits, .activity, .insights],
        tokenCategories: Set(TokenCategory.allCases),
        limitsPolicy: SchedulePolicy(
            defaultInterval: .seconds(900), minimumInterval: .seconds(300), maximumInterval: .seconds(3600),
            staleAfter: .seconds(1800), manualFloor: .seconds(60), needsNetwork: true))
    static let mockOther = ProviderDescriptor(
        id: ProviderID(rawValue: "other-tool"), displayName: "Other Tool", symbolName: "terminal",
        capabilities: .limits,
        tokenCategories: [], limitsPolicy: mockClaudeCode.limitsPolicy)
}

extension LimitsReport {
    static let mockLimits = LimitsReport(
        provider: .claudeCode,
        windows: [
            UsageWindow(
                label: "Current session", kind: .session, usedPercent: 23, isBelowOne: false,
                resetsAt: .now.addingTimeInterval(7800)),
            UsageWindow(
                label: "Current week (all models)", kind: .weekly, usedPercent: 74, isBelowOne: false,
                resetsAt: .now.addingTimeInterval(4 * 86400)),
            UsageWindow(
                label: "Current week (Opus)", kind: .weekly, usedPercent: 93, isBelowOne: false,
                resetsAt: .now.addingTimeInterval(4 * 86400)),
        ],
        billingNote: nil, insights: .mock, rawOutput: nil)
    static let mockOtherLimits = LimitsReport(
        provider: ProviderID(rawValue: "other-tool"),
        windows: [
            UsageWindow(
                label: "Daily requests", kind: .other, usedPercent: 0.4, isBelowOne: true,
                resetsAt: .now.addingTimeInterval(600))
        ],
        billingNote: nil, insights: nil, rawOutput: nil)
}

extension Insights {
    static let mock = Insights(
        note: "Approximate, based on local sessions on this machine.",
        periods: [
            Period(
                label: "Last 24h", summary: "206 requests · 5 sessions",
                shares: [Share(label: "At >150k context", percent: 62)],
                rankings: [
                    Ranking(
                        title: "Skills",
                        items: [
                            Share(label: "/skill-a", percent: 35), Share(label: "/skill-b", percent: 23),
                            Share(label: "/skill-c", percent: 21), Share(label: "/skill-d", percent: 2),
                        ]),
                    Ranking(title: "Plugins", items: [Share(label: "plugin-a", percent: 56)]),
                ]),
            Period(
                label: "Last 7d", summary: "3350 requests · 88 sessions",
                shares: [
                    Share(label: "At >150k context", percent: 54), Share(label: "Subagent-heavy sessions", percent: 13),
                ],
                rankings: [Ranking(title: "Skills", items: [Share(label: "/skill-a", percent: 42)])]),
        ])
}

extension ActivityReport {
    static let mockActivity = ActivityReport(
        provider: .claudeCode,
        // The last 7 days up to today, so the section finds today.
        days: [1.1, 3.4, 2.0, 5.1, 4.4, 0.8, 4.2].enumerated().map { index, millions in
            ActivityDay(
                day: DayKey(.now.addingTimeInterval(Double(index - 6) * 86400), calendar: .current), requests: 668,
                sessions: 8,
                tokens: TokenCounts(
                    input: 12_000, output: 812_000, cacheWrite: 300_000, cacheRead: Int(millions * 1_000_000)),
                byModel: [:])
        },
        skippedLines: 0)
}

extension GitHubReport {
    static let mockGitHub = GitHubReport(
        calendar: ContributionCalendar(
            login: "octocat",
            weeks: (0..<26).map { week in
                (0..<7).map { day in
                    let index = week * 7 + day
                    let count = (index * 7 + index / 3) % 9
                    return ContributionDay(
                        date: DayKey(rawValue: "d\(index)"), count: count,
                        level: ContributionLevel(rawValue: count / 2) ?? .fourth)
                }
            },
            totalContributions: 1234),
        stats: ContributionStats(today: 5, thisWeek: 21, currentStreak: 12, streakNeedsToday: false, longestStreak: 30))
}

// MARK: - Previews: every row of SPEC §11.3, light and dark side by side.

private struct BothSchemes: View {
    let state: AppState
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                PopoverView().environment(state).background(.background).environment(\.colorScheme, scheme)
            }
        }
    }
}

private let unparseable = "Weird output\n  ▌▌▌ 23% ???"

#Preview("Loaded, one provider") { BothSchemes(state: .mock()) }
#Preview("Loaded, two providers") { BothSchemes(state: .mock(secondProvider: true)) }
#Preview("Provider disabled") { BothSchemes(state: AppState(providers: [], github: .loaded(.fresh(.mockGitHub)))) }
#Preview("Not configured") {
    BothSchemes(
        state: .mock(
            limits: .notConfigured(.toolNotInstalled), activity: .notConfigured(.noLocalData),
            github: .notConfigured(.githubTokenMissing)))
}
#Preview("First load") {
    BothSchemes(
        state: .mock(
            limits: .loading(previous: nil), activity: .loading(previous: nil), github: .loading(previous: nil)))
}
#Preview("Stale") { BothSchemes(state: .mock(limits: .loaded(.old(.mockLimits)), github: .loaded(.old(.mockGitHub)))) }
#Preview("Failed, has previous") {
    BothSchemes(
        state: .mock(
            limits: .failed(.timedOut, previous: .fresh(.mockLimits)),
            activity: .failed(.io("Permission denied"), previous: .fresh(.mockActivity)),
            github: .failed(.offline, previous: .fresh(.mockGitHub))))
}
#Preview("Failed, no previous") {
    BothSchemes(
        state: .mock(
            limits: .failed(.notLoggedIn, previous: nil), activity: .failed(.io("Permission denied"), previous: nil),
            github: .failed(.unauthorized, previous: nil)))
}
#Preview("Unsupported plan") {
    BothSchemes(
        state: .mock(
            limits: .notConfigured(
                .unsupportedPlan(note: "Plan limits need a Claude subscription login in Claude Code"))))
}
#Preview("Reset passed (FR-11)") {
    let passed = LimitsReport(
        provider: .claudeCode,
        windows: [
            UsageWindow(
                label: "Current session", kind: .session, usedPercent: 97, isBelowOne: false,
                resetsAt: .now.addingTimeInterval(-60)),
            UsageWindow(
                label: "Current week (all models)", kind: .weekly, usedPercent: 41, isBelowOne: false,
                resetsAt: .now.addingTimeInterval(1500)),
        ],
        billingNote: nil, insights: nil, rawOutput: nil)
    BothSchemes(state: .mock(limits: .loading(previous: .fresh(passed))))
}
#Preview("Unparseable") {
    BothSchemes(state: .mock(limits: .failed(.unparseable(rawOutput: unparseable), previous: .fresh(.mockLimits))))
}
