import ContribusageCore
import ContribusageGitHub
import SwiftUI

struct GitHubSection: View {
    let state: SourceState<GitHubReport>

    var body: some View {
        let snapshot = state.snapshot
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(
                title: "GitHub", symbolName: "square.grid.3x3.fill", subtitle: snapshot.map { "@\($0.value.login)" },
                fetchedAt: snapshot?.fetchedAt)
            SectionStateView(
                state: state, displayName: "GitHub", staleAfter: GitHubReport.staleAfter, placeholder: .placeholder,
                content: GitHubContent.init)
        }
    }
}

private struct GitHubContent: View {
    let report: GitHubReport

    var body: some View {
        Heatmap(days: report.days)
        Text(
            "Today \(report.stats.today) · Streak \(report.stats.currentStreak) days · Year \(report.totalContributions.formatted())"
        )
        .font(.caption)
    }
}

// ponytail: plain grid of weeks; T-3.5 owns the palette, hover, keyboard and VoiceOver.
private struct Heatmap: View {
    let days: [ContributionDay]

    var body: some View {
        let weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        HStack(spacing: 2) {
            ForEach(weeks.indices, id: \.self) { week in
                VStack(spacing: 2) {
                    ForEach(weeks[week], id: \.date) { day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                day.level == .none
                                    ? AnyShapeStyle(.quaternary)
                                    : AnyShapeStyle(.green.opacity(0.25 * Double(day.level.rawValue)))
                            )
                            .frame(width: 10, height: 10)
                            .help("\(day.date.rawValue): \(day.count) contributions")
                    }
                }
            }
        }
    }
}

extension GitHubReport {
    static let placeholder = GitHubReport(
        login: "octocat",
        days: (0..<182).map { ContributionDay(date: DayKey(rawValue: "\($0)"), count: 0, level: .none) },
        totalContributions: 0,
        stats: ContributionStats(today: 0, thisWeek: 0, currentStreak: 0, streakNeedsToday: false, longestStreak: 0))
}
