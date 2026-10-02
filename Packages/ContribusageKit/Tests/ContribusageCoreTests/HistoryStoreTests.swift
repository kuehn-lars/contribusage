import ContribusageCore
import ContribusageTestSupport
import Foundation
import Testing

/// SPEC §8.3.4 and FR-29: days freeze 48 h after their end, are never recomputed, and are kept 365 days.

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let now = Date(timeIntervalSince1970: 1_790_942_400)  // 2026-10-02 12:00 UTC

private func day(_ raw: String, requests: Int) -> ActivityDay {
    ActivityDay(
        day: DayKey(rawValue: raw), requests: requests, sessions: 1, tokens: TokenCounts(input: requests),
        byModel: ["m": TokenCounts(input: requests)])
}

/// 09-29 ended 60 h before `now` and freezes; 09-30 ended 36 h before and stays live.
@Test func freezesDaysMoreThan48HoursPastAndShowsYoungerDaysLive() throws {
    var store = try HistoryStore(provider: .fake, paths: AppPaths.temporary(), fileReader: LiveFileReader())
    let live = [day("2026-09-29", requests: 1), day("2026-09-30", requests: 2), day("2026-10-02", requests: 3)]

    let shown = try store.merge(live, now: now, calendar: calendar)

    #expect(shown == live)
    #expect(try store.merge([], now: now, calendar: calendar) == [day("2026-09-29", requests: 1)])
}

/// A deleted transcript or a later recount does not change a frozen day, also after a restart.
@Test func frozenDaysAreNeverRecomputedAndSurviveRestart() throws {
    let paths = AppPaths.temporary()
    var store = try HistoryStore(provider: .fake, paths: paths, fileReader: LiveFileReader())
    _ = try store.merge([day("2026-09-20", requests: 10)], now: now, calendar: calendar)

    var reloaded = try HistoryStore(provider: .fake, paths: paths, fileReader: LiveFileReader())
    let shown = try reloaded.merge(
        [day("2026-09-20", requests: 3), day("2026-10-01", requests: 1)], now: now, calendar: calendar)
    #expect(shown == [day("2026-09-20", requests: 10), day("2026-10-01", requests: 1)])
    #expect(try reloaded.merge([], now: now, calendar: calendar) == [day("2026-09-20", requests: 10)])
}

/// A clock or time zone change can move a frozen day back inside the last 48 h: it still shows once, frozen.
@Test func aFrozenDayShowsOnceWhenTheCutoffMovesBack() throws {
    var store = try HistoryStore(provider: .fake, paths: AppPaths.temporary(), fileReader: LiveFileReader())
    _ = try store.merge([day("2026-09-29", requests: 1)], now: now, calendar: calendar)

    let shown = try store.merge(
        [day("2026-09-29", requests: 5), day("2026-09-30", requests: 2)], now: now.addingTimeInterval(-86_400),
        calendar: calendar)

    #expect(shown == [day("2026-09-29", requests: 1), day("2026-09-30", requests: 2)])
}

/// 365 days: today and the 364 before it. Older days are neither frozen nor kept.
@Test func keeps365Days() throws {
    let paths = AppPaths.temporary()
    var store = try HistoryStore(provider: .fake, paths: paths, fileReader: LiveFileReader())
    let earlier = now.addingTimeInterval(-2 * 86_400)
    let frozen = try store.merge(
        [day("2025-09-30", requests: 1), day("2025-10-02", requests: 2), day("2025-10-03", requests: 3)],
        now: earlier, calendar: calendar)
    #expect(frozen == [day("2025-10-02", requests: 2), day("2025-10-03", requests: 3)])

    let shown = try store.merge([day("2025-10-02", requests: 2)], now: now, calendar: calendar)

    #expect(shown == [day("2025-10-03", requests: 3)])
    // At `earlier` 2025-10-02 is still within 365 days, so only the persisted prune removes it.
    var reloaded = try HistoryStore(provider: .fake, paths: paths, fileReader: LiveFileReader())
    #expect(try reloaded.merge([], now: earlier, calendar: calendar) == [day("2025-10-03", requests: 3)])
}

/// Keyed by provider: each history lives in its own `providers/<id>/history.json`.
@Test func historiesAreKeptPerProvider() throws {
    let paths = AppPaths.temporary()
    var fake = try HistoryStore(provider: .fake, paths: paths, fileReader: LiveFileReader())
    _ = try fake.merge([day("2026-09-20", requests: 1)], now: now, calendar: calendar)

    var other = try HistoryStore(provider: ProviderID(rawValue: "other"), paths: paths, fileReader: LiveFileReader())
    #expect(try other.merge([], now: now, calendar: calendar).isEmpty)
    let file = paths.providerFolder(.fake).appending(path: "history.json").path(percentEncoded: false)
    #expect(FileManager.default.fileExists(atPath: file))
}

/// An unreadable or newer history throws and stays on disk untouched.
@Test func unreadableHistoryIsNeverDiscarded() throws {
    let paths = AppPaths.temporary()
    let file = paths.providerFolder(.fake).appending(path: "history.json")
    try JSONStore.createFolder(file.deletingLastPathComponent())
    let newer = Data(#"{"schemaVersion":99,"value":{}}"#.utf8)
    try newer.write(to: file)

    #expect(throws: PersistenceError.unsupportedSchemaVersion(99)) {
        try HistoryStore(provider: .fake, paths: paths, fileReader: LiveFileReader())
    }
    #expect(try Data(contentsOf: file) == newer)
}
