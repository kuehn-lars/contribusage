import Foundation

/// A provider's frozen daily aggregates in `providers/<id>/history.json` (SPEC §8.3.4, §10.7, FR-29). A day freezes
/// once it ended more than 48 h ago and is never recomputed after that, so deleted transcripts keep their history.
public struct HistoryStore: Sendable {
    /// Frozen days, oldest first.
    private var days: [ActivityDay]

    private let file: URL

    private struct History: PersistedFile {
        static let schemaVersion = 1
        var days: [ActivityDay]
    }

    /// Throws for an unreadable or other-version file and leaves it on disk: history is never discarded.
    public init(provider: ProviderID, paths: AppPaths, fileReader: any FileReading) throws {
        file = paths.providerFolder(provider).appending(path: "history.json")
        days = try JSONStore.read(History.self, from: file, using: fileReader)?.days ?? []
    }

    /// Freezes the live days that are due, drops days beyond 365 and returns what to show, oldest first: frozen days,
    /// then the live days younger than 48 h. `live` holds the provider's current aggregates by day in `calendar`,
    /// oldest first.
    public mutating func merge(_ live: [ActivityDay], now: Date, calendar: Calendar) throws -> [ActivityDay] {
        // A day ended more than 48 h ago when it lies before the day of `now - 48 h`.
        let firstLive = DayKey(now.addingTimeInterval(-48 * 3600), calendar: calendar)
        let oldestKept = DayKey(calendar.date(byAdding: .day, value: -364, to: now)!, calendar: calendar)
        // A frozen day wins over its live count, also when a clock or zone change moves it back past `firstLive`.
        let frozen = Set(days.map(\.day))
        let unfrozen = live.filter { !frozen.contains($0.day) }
        let updated = (days + unfrozen.filter { $0.day < firstLive })
            .filter { $0.day >= oldestKept }
            .sorted { $0.day < $1.day }
        if updated != days {
            try JSONStore.write(History(days: updated), to: file)
            days = updated
        }
        return days + unfrozen.filter { $0.day >= firstLive }
    }
}
