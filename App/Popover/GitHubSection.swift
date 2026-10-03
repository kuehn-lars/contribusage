import ContribusageCore
import ContribusageGitHub
import SwiftUI

struct GitHubSection: View {
    let state: SourceState<GitHubReport>
    @Environment(AppState.self) private var appState

    var body: some View {
        let snapshot = state.snapshot
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(
                title: "GitHub", symbolName: "square.grid.3x3.fill",
                subtitle: snapshot.map { "@\($0.value.calendar.login)" }, fetchedAt: snapshot?.fetchedAt)
            SectionStateView(
                state: state, displayName: "GitHub", staleAfter: GitHubReport.policy.staleAfter,
                placeholder: .placeholder, retry: appState.refresh, content: GitHubContent.init)
        }
    }
}

private struct GitHubContent: View {
    let report: GitHubReport

    var body: some View {
        Text(report.statsText).font(.caption)
    }
}

extension GitHubReport {
    /// Shared with Copy Statistics (FR-42).
    var statsText: String {
        String(
            localized:
                "Today \(stats.today) · Streak \(stats.currentStreak) days · Year \(calendar.totalContributions.formatted())"
        )
    }
}

extension GitHubReport {
    static let placeholder = GitHubReport(
        calendar: ContributionCalendar(
            login: "octocat",
            weeks: (0..<26).map { week in
                (0..<7).map { ContributionDay(date: DayKey(rawValue: "\(week * 7 + $0)"), count: 0, level: .none) }
            },
            totalContributions: 0),
        stats: ContributionStats(today: 0, thisWeek: 0, currentStreak: 0, streakNeedsToday: false, longestStreak: 0))
}
