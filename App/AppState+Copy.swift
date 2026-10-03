import AppKit
import ContribusageCore
import Foundation

/// The two texts the app copies: statistics from the popover (FR-42), diagnostics from Settings (FR-36, ADR-030).
extension AppState {
    /// FR-42: what the popover shows, in its order, as plain text. Insights give every period, not only the one picked.
    func statistics(at now: Date) -> String {
        var sections: [[String]] = enabledProviders.map { group in
            let name = group.descriptor.displayName
            var lines = [header(name, group.limits?.snapshot?.fetchedAt)]
            lines += values(group.limits, name) { report in
                report.windows.map { window in
                    ["\(window.label): \(window.percentText(at: now))", window.resetText(at: now)]
                        .compactMap(\.self).joined(separator: " · ")
                }
            }
            lines += values(group.activity, name) { report in
                let figures = ActivitySection.Figures(report: report, now: now)
                let week = figures.week.map {
                    "\($0.day.formatted(.dateTime.weekday())) \(ActivitySection.Figures.compact($0.tokens))"
                }
                return [
                    figures.todayText, figures.categoriesText(group.descriptor.tokenCategories),
                    String(localized: "Last 7 days: \(week.joined(separator: " · "))"),
                ]
            }
            if UserDefaults.standard.object(forKey: "showInsights") as? Bool ?? true, let insights = group.insights {
                lines += insightsLines(insights)
            }
            return lines
        }
        let login = github.snapshot.map { " @\($0.value.calendar.login)" } ?? ""
        sections.append(
            [header("GitHub" + login, github.snapshot?.fetchedAt)] + values(github, "GitHub") { [$0.statsText] })
        return sections.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
    }

    /// FR-42: copies `statistics(at:)` to the clipboard.
    func copyStatistics() {
        copy(statistics(at: .now))
    }

    /// US-10, FR-36: copies `diagnostics()` to the clipboard.
    func copyDiagnostics() {
        Task { copy(await diagnostics()) }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// The app, the Mac, every registered provider and GitHub. Never a token: the GitHub token never reaches `AppState`.
    /// English in every language, since it goes into bug reports (ADR-031).
    func diagnostics() async -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        var lines = [
            "contribusage \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Chip: \(Self.chip)",
        ]
        for group in providers {
            lines += ["", "\(group.descriptor.displayName): \(enabledIDs.contains(group.id) ? "enabled" : "disabled")"]
            if let limits = group.limits { lines.append("Limits: \(limits.diagnostics)") }
            if let activity = group.activity {
                lines.append("Activity: \(activity.diagnostics)")
                if let report = activity.snapshot?.value { lines.append("Skipped lines: \(report.skippedLines)") }
            }
            if let provider = registry?.providers.first(where: { $0.descriptor.id == group.id }) {
                lines += await provider.diagnostics()
            }
        }
        lines += ["", "GitHub: \(github.diagnostics)"]
        return lines.joined(separator: "\n")
    }

    /// "Apple M3".
    private static var chip: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var bytes = [UInt8](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0)
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}

/// The section's title and, when it has values, when they were fetched.
private func header(_ title: String, _ fetchedAt: Date?) -> String {
    fetchedAt.map { String(localized: "\(title) · updated \($0.formatted(date: .abbreviated, time: .shortened))") }
        ?? title
}

/// The shown values (current or previous), else a failure's §13 message; a source that is loading or not configured
/// adds nothing.
private func values<Value>(_ state: SourceState<Value>?, _ name: String, _ lines: (Value) -> [String]) -> [String] {
    if let snapshot = state?.snapshot { return lines(snapshot.value) }
    if case .failed(let error, _) = state { return [error.message(displayName: name)] }
    return []
}

/// `InsightsSection`'s content per period: summary, shares, then the top three of each ranking.
private func insightsLines(_ insights: Insights) -> [String] {
    func line(_ share: Insights.Share, indent: String) -> String {
        indent + share.label + (share.percent.map { " " + $0.formatted(.percent) } ?? "")
    }
    var lines = [String(localized: "Insights") + (insights.note.map { " (\($0))" } ?? "")]
    for period in insights.periods {
        lines.append("\(period.label): \(period.summary)")
        lines += period.shares.map { line($0, indent: "  ") }
        for ranking in period.rankings {
            lines.append("  \(ranking.title)")
            lines += ranking.shown.map { line($0, indent: "    ") }
        }
    }
    return lines
}
