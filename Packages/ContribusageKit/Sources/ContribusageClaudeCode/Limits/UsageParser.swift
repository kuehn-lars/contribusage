import ContribusageCore
import Foundation

/// Reads `claude -p /usage` output (SPEC §8.1.3, §8.1.4).
public enum UsageParser {
    /// P-1 to P-11. Whether the billing note means a subscription is the provider's call (P-10, T-2.5).
    /// `fallbackZone` applies when a reset clause names no known zone (P-6).
    public static func report(from output: String, now: Date, fallbackZone: TimeZone = .current) -> LimitsReport {
        let text = output.replacing(/\e\[[^A-Za-z]*[A-Za-z]/, with: "")
        let lines = text.split(whereSeparator: \.isNewline)
        let insights = text.firstRange(of: /^[ \t]*What['’]s contributing/.anchorsMatchLineEndings())
        return LimitsReport(
            provider: .claudeCode,
            windows: lines.compactMap { window(in: $0, now: now, fallbackZone: fallbackZone) },
            billingNote: lines.lazy.map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty },
            insights: insights.flatMap { self.insights(in: text[$0.lowerBound...]) },
            rawOutput: output)
    }

    /// P-11: after the heading, an unindented line with " · " opens a period, indented lines fill it,
    /// any other line joins the note. No period, no insights.
    private static func insights(in block: Substring) -> Insights? {
        var note: [String] = []
        var periods: [(label: Substring, summary: Substring, lines: [String])] = []
        for line in block.split(whereSeparator: \.isNewline).dropFirst() {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            if line.first?.isWhitespace == true, !periods.isEmpty {
                periods[periods.count - 1].lines.append(text)
            } else if let header = text.wholeMatch(of: /(?<label>.+?) · (?<summary>.+)/) {
                periods.append((header.label, header.summary, []))
            } else {
                note.append(text)
            }
        }
        guard !periods.isEmpty else { return nil }
        return Insights(
            note: note.isEmpty ? nil : note.joined(separator: " "),
            periods: periods.map { period(label: $0.label, summary: $0.summary, lines: $0.lines) })
    }

    private static func period(label: Substring, summary: Substring, lines: [String]) -> Insights.Period {
        var shares: [Insights.Share] = []
        var rankings: [Insights.Ranking] = []
        for line in lines {
            if let top = line.wholeMatch(of: /Top (?<title>[^:]+):\s*(?<items>.*)/) {
                let items = top.items.split(separator: ", ").map { share(String($0)) }
                rankings.append(Insights.Ranking(title: capitalized(top.title), items: items))
            } else {
                shares.append(share(line))
            }
        }
        return Insights.Period(label: String(label), summary: String(summary), shares: shares, rankings: rankings)
    }

    /// "72% of your usage was at >150k context", "/skill-a 29%"; anything else keeps its text and no percent.
    private static func share(_ text: String) -> Insights.Share {
        if let usage = text.wholeMatch(of: /(?<pct>\d+)% of your usage (?:was |came from )?(?<what>.+)/) {
            return Insights.Share(label: capitalized(usage.what), percent: Int(usage.pct))
        }
        if let item = text.wholeMatch(of: /(?<name>.+) (?<pct>\d+)%/) {
            return Insights.Share(label: String(item.name), percent: Int(item.pct))
        }
        return Insights.Share(label: text, percent: nil)
    }

    private static func capitalized(_ text: Substring) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    /// P-3 to P-5; nil for any other line.
    private static func window(in line: Substring, now: Date, fallbackZone: TimeZone) -> UsageWindow? {
        // P-3, with the optional "<" captured for P-5.
        let windowLine =
            #/
            \s* (?<label>[^:]+) : \s* (?<lt><)? \s* (?<pct>\d+(?:\.\d+)?) % \s* used
            (?: .*? \b resets \s+ (?<reset>.+?) )? \s*
            /#
        guard
            let match = try? windowLine.wholeMatch(in: line),
            let percent = Double(match.pct)
        else { return nil }
        let label = match.label.trimmingCharacters(in: .whitespaces)
        let isBelowOne = match.lt != nil
        return UsageWindow(
            label: label,
            kind: kind(of: label),
            usedPercent: isBelowOne ? 0.5 : percent,
            isBelowOne: isBelowOne,
            resetsAt: match.reset.flatMap { resetDate(String($0), now: now, fallbackZone: fallbackZone) }
        )
    }

    /// SPEC §8.1.4: an unknown label is kept as `other`, never dropped.
    private static func kind(of label: String) -> WindowKind {
        if label == "Current session" { return .session }
        return label.hasPrefix("Current week") ? .weekly : .other
    }

    /// P-6 to P-9; nil when no format fits.
    private static func resetDate(_ clause: String, now: Date, fallbackZone: TimeZone) -> Date? {
        var text = clause
        var zone = fallbackZone
        if let match = clause.wholeMatch(of: /(?<when>.*?)\s*\((?<zone>[^()]*)\)/) {
            text = String(match.when)
            zone = TimeZone(identifier: String(match.zone)) ?? fallbackZone
        }
        text = text.replacing(/\s*([ap])m\b/.ignoresCase()) { " \($0.1.uppercased())M" }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        // P-7 in order; a dated format gets a year (P-8), a time only one the next occurrence.
        let formats = [
            ("MMM d 'at' h:mm a", dated: true), ("MMM d 'at' h a", dated: true), ("MMM d", dated: true),
            ("h:mm a", dated: false), ("h a", dated: false),
        ]
        for (format, dated) in formats {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: text) else { continue }
            var parts = calendar.dateComponents([.month, .day, .hour, .minute], from: parsed)
            guard dated else {
                return calendar.nextDate(
                    after: now, matching: DateComponents(hour: parts.hour, minute: parts.minute),
                    matchingPolicy: .nextTime)
            }
            parts.year = calendar.component(.year, from: now)
            guard let date = calendar.date(from: parts) else { return nil }
            return date < now.addingTimeInterval(-24 * 3600) ? calendar.date(byAdding: .year, value: 1, to: date) : date
        }
        return nil
    }
}
