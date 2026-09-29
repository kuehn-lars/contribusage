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
        billingNote: nil, insights: "Most usage came from long sessions in one project.", rawOutput: nil)
    static let mockOtherLimits = LimitsReport(
        provider: ProviderID(rawValue: "other-tool"),
        windows: [
            UsageWindow(
                label: "Daily requests", kind: .other, usedPercent: 0.4, isBelowOne: true,
                resetsAt: .now.addingTimeInterval(600))
        ],
        billingNote: nil, insights: nil, rawOutput: nil)
}

extension ActivityReport {
    static let mockActivity = ActivityReport(
        provider: .claudeCode,
        days: [1.1, 3.4, 2.0, 5.1, 4.4, 0.8, 4.2].enumerated().map { index, millions in
            ActivityDay(
                day: DayKey(rawValue: "2026-09-\(22 + index)"), requests: 668, sessions: 8,
                tokens: TokenCounts(output: Int(millions * 1_000_000)), byModel: [:])
        },
        skippedLines: 0)
}

extension GitHubReport {
    static let mockGitHub = GitHubReport(
        calendar: ContributionCalendar(
            login: "octocat",
            days: (0..<182).map { index in
                let count = (index * 7 + index / 3) % 9
                return ContributionDay(
                    date: DayKey(rawValue: "d\(index)"), count: count,
                    level: ContributionLevel(rawValue: count / 2) ?? .fourth)
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
