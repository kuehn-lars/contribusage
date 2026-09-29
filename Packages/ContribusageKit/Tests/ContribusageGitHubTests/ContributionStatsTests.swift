import ContribusageCore
import ContribusageGitHub
import Foundation
import Testing

/// Consecutive days from `start`, one per count.
private func days(from start: String, _ counts: [Int]) throws -> [ContributionDay] {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = .gmt
    let first = try Date("\(start)T00:00:00Z", strategy: .iso8601)
    return counts.enumerated().map { offset, count in
        let date = utc.date(byAdding: .day, value: offset, to: first)!
        return ContributionDay(
            date: DayKey(rawValue: date.formatted(.iso8601.year().month().day())), count: count, level: .none)
    }
}

private func calendar(firstWeekday: Int = 2, zone: String = "UTC") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    calendar.firstWeekday = firstWeekday
    return calendar
}

/// Wednesday 2026-09-30, midday UTC.
private let wednesday = try! Date("2026-09-30T12:00:00Z", strategy: .iso8601)

/// SPEC §8.4.4: today, the week from the locale's first weekday, both streaks. The entry after today (a
/// GitHub day boundary ahead of the calendar's) counts nowhere yet. Monday first: 16 + 32 + 64; Sunday first adds 8.
@Test(arguments: [(2, 112), (1, 120)])
func statsFollowSpec(firstWeekday: Int, thisWeek: Int) throws {
    // 09-14 … 09-16 is a three-day run; 09-27 … 09-30 (today) the longest at four; 10-01 would make it five.
    let days = try days(from: "2026-09-14", [1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 8, 16, 32, 64, 128])
    let stats = ContributionStats(days: days, now: wednesday, calendar: calendar(firstWeekday: firstWeekday))
    #expect(
        stats
            == ContributionStats(
                today: 64, thisWeek: thisWeek, currentStreak: 4, streakNeedsToday: false, longestStreak: 4))
}

/// Today 0 so far, or not in the calendar yet: the streak runs to yesterday and asks for today.
@Test(arguments: [[3, 5, 0], [3, 5]])
func streakEndingYesterdayNeedsToday(counts: [Int]) throws {
    let stats = ContributionStats(days: try days(from: "2026-09-28", counts), now: wednesday, calendar: calendar())
    #expect(stats.today == 0)
    #expect(stats.currentStreak == 2)
    #expect(stats.streakNeedsToday)
}

/// No streak to extend: nothing is asked of today.
@Test func noStreakNeedsNothing() throws {
    let stats = ContributionStats(days: try days(from: "2026-09-28", [3, 0, 0]), now: wednesday, calendar: calendar())
    #expect(stats.currentStreak == 0)
    #expect(!stats.streakNeedsToday)
    #expect(stats.longestStreak == 1)
}

/// The calendar's time zone decides which entry is today (R-4 picks the zone).
@Test func timeZoneDecidesToday() throws {
    let lateUTC = try Date("2026-09-30T23:30:00Z", strategy: .iso8601)
    let days = try days(from: "2026-09-30", [1, 2])
    #expect(ContributionStats(days: days, now: lateUTC, calendar: calendar()).today == 1)
    #expect(ContributionStats(days: days, now: lateUTC, calendar: calendar(zone: "Asia/Tokyo")).today == 2)
}
