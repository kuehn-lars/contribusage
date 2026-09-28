import ContribusageCore
import Foundation

/// Reads the usage windows out of `claude -p /usage` output (SPEC §8.1.3 P-1 to P-9, §8.1.4).
public enum UsageParser {
    /// `fallbackZone` applies when the reset clause names no known zone (P-6).
    public static func windows(in output: String, now: Date, fallbackZone: TimeZone = .current) -> [UsageWindow] {
        let text = output.replacing(/\e\[[^A-Za-z]*[A-Za-z]/, with: "")
        // P-3, with the optional "<" captured for P-5.
        let windowLine =
            #/
            \s* (?<label>[^:]+) : \s* (?<lt><)? \s* (?<pct>\d+(?:\.\d+)?) % \s* used
            (?: .*? \b resets \s+ (?<reset>.+?) )? \s*
            /#
        return text.split(whereSeparator: \.isNewline).compactMap { line in
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
