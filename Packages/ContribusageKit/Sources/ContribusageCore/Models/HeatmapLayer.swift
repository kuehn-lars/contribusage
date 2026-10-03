import Foundation

/// One source's days in the shared heatmap (FR-48, ADR-032): GitHub's contributions or a provider's total tokens.
public struct HeatmapLayer: Sendable, Equatable {
    public let id: BlockID
    /// The source's name in the legend, the tooltip and Copy: "GitHub" or the provider's.
    public let name: String
    /// Tokens or contributions; a missing day is "no data".
    public let values: [DayKey: Int]
    /// 0...4; a missing day is drawn like 0.
    public let levels: [DayKey: Int]

    /// GitHub's layer, with its `contributionLevel`s (FR-20).
    public init(id: BlockID, name: String, values: [DayKey: Int], levels: [DayKey: Int]) {
        self.id = id
        self.name = name
        self.values = values
        self.levels = levels
    }

    /// A provider's layer: 0 for a day without tokens, otherwise the quartile of the day among the non-zero `values`, so
    /// the busiest day is 4 (FR-48). `values` holds the shown range only.
    public static func quartiled(_ id: BlockID, name: String, values: [DayKey: Int]) -> HeatmapLayer {
        let active = values.values.filter { $0 > 0 }.sorted()
        let levels = values.mapValues { value in
            guard value > 0 else { return 0 }
            let atMost = active.firstIndex { $0 > value } ?? active.count
            return (4 * atMost + active.count - 1) / active.count
        }
        return HeatmapLayer(id: id, name: name, values: values, levels: levels)
    }

    /// The shown range (FR-20, FR-48): 26 week columns from Sunday, as GitHub's, the last ending with `now`'s day.
    public static func days(through now: Date, calendar: Calendar) -> [DayKey] {
        let today = calendar.startOfDay(for: now)
        let count = 25 * 7 + calendar.component(.weekday, from: today)  // weekday 1 is Sunday
        return (1 - count...0).map { DayKey(calendar.date(byAdding: .day, value: $0, to: today)!, calendar: calendar) }
    }

    /// The sum over the shown range, for Copy (FR-42) and the VoiceOver label (SPEC §11.7).
    public var total: Int { values.values.reduce(0, +) }

    /// The day `by` columns (weeks) and rows (weekdays) away in the grid of `days(through:calendar:)`, or `index` when
    /// that leaves the grid (NFR-8).
    public static func step(from index: Int, by move: (x: Int, y: Int), count: Int) -> Int {
        let row = index % 7 + move.y
        let target = index + 7 * move.x + move.y
        return (0..<7).contains(row) && (0..<count).contains(target) ? target : index
    }

    /// "1.2M tokens", "5 contributions", or "no data" (FR-49).
    public func text(on day: DayKey, locale: Locale = .autoupdatingCurrent) -> String {
        values[day].map { text($0, locale: locale) } ?? String(localized: "no data", bundle: .module, locale: locale)
    }

    /// A value of this layer, also a total (FR-42).
    public func text(_ value: Int, locale: Locale = .autoupdatingCurrent) -> String {
        if id == .github {
            return String(localized: "\(value) contributions", bundle: .module, locale: locale)
        }
        let tokens = value.formatted(.number.notation(.compactName).locale(locale))
        return String(localized: "\(tokens) tokens", bundle: .module, locale: locale)
    }

    /// FR-49's tooltip and VoiceOver line: "2026-09-27 · Claude Code: 1.2M tokens · GitHub: 5 contributions".
    public static func line(_ day: DayKey, layers: [HeatmapLayer], locale: Locale = .autoupdatingCurrent) -> String {
        ([day.rawValue] + layers.map { "\($0.name): \($0.text(on: day, locale: locale))" }).joined(separator: " · ")
    }
}
