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
        Heatmap(weeks: report.calendar.weeks.suffix(26))  // FR-20
        Text(
            "Today \(report.stats.today) · Streak \(report.stats.currentStreak) days · Year \(report.calendar.totalContributions.formatted())"
        )
        .font(.caption)
    }
}

// ponytail: plain grid of weeks; T-5.11 owns the palette, keyboard and VoiceOver.
private struct Heatmap: View {
    let weeks: ArraySlice<[ContributionDay]>

    var body: some View {
        WeekColumns {
            ForEach(Array(weeks.joined()), id: \.date) { day in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        day.level == .none
                            ? AnyShapeStyle(.quaternary)
                            : AnyShapeStyle(.green.opacity(0.25 * Double(day.level.rawValue)))
                    )
                    .help("\(day.date.rawValue): \(day.count) contributions")
            }
        }
    }
}

/// Days in columns of 7, top-aligned, as square cells sharing the proposed width; every column but the last is full, as
/// in GitHub's weeks after the first. The height follows from the width and never from the proposal: the menu bar window
/// proposes too little height, and `aspectRatio` cells shrank to dots.
private struct WeekColumns: Layout {
    private let gap: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let columns = (subviews.count + 6) / 7
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? CGFloat(columns) * (10 + gap) - gap
        let rows = min(subviews.count, 7)
        return CGSize(width: width, height: CGFloat(rows) * (side(width, columns) + gap) - gap)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let side = side(bounds.width, (subviews.count + 6) / 7)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + CGFloat(index / 7) * (side + gap),
                    y: bounds.minY + CGFloat(index % 7) * (side + gap)),
                proposal: ProposedViewSize(width: side, height: side))
        }
    }

    private func side(_ width: CGFloat, _ columns: Int) -> CGFloat {
        max((width - gap * CGFloat(columns - 1)) / CGFloat(columns), 0)
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
