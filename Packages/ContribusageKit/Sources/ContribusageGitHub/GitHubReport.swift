import ContribusageCore
import Foundation

/// SPEC §10.5.
public enum ContributionLevel: Int, Sendable, Codable { case none, first, second, third, fourth }

public struct ContributionDay: Sendable, Codable, Equatable {
    public let date: DayKey
    public let count: Int
    public let level: ContributionLevel

    public init(date: DayKey, count: Int, level: ContributionLevel) {
        self.date = date
        self.count = count
        self.level = level
    }
}

public struct ContributionStats: Sendable, Codable, Equatable {
    public let today: Int
    public let thisWeek: Int
    public let currentStreak: Int
    /// Today is 0 so far, the streak is counted up to yesterday.
    public let streakNeedsToday: Bool
    public let longestStreak: Int

    public init(today: Int, thisWeek: Int, currentStreak: Int, streakNeedsToday: Bool, longestStreak: Int) {
        self.today = today
        self.thisWeek = thisWeek
        self.currentStreak = currentStreak
        self.streakNeedsToday = streakNeedsToday
        self.longestStreak = longestStreak
    }

    /// FR-19, SPEC §8.4.4, over consecutive `days` in API order. `calendar` sets the day boundary (its time zone,
    /// R-4) and the week start (its first weekday, ADR-021). Days after today (GitHub's day ahead of
    /// `calendar`'s) count nowhere.
    public init(days: [ContributionDay], now: Date, calendar: Calendar) {
        let today = DayKey(now, calendar: calendar)
        let weekStart = DayKey(calendar.dateInterval(of: .weekOfYear, for: now)!.start, calendar: calendar)
        let past = days.filter { $0.date <= today }
        let todayCount = past.last(where: { $0.date == today })?.count ?? 0
        // Today at 0 so far (or not in the calendar yet) leaves the streak ending yesterday.
        let current = past.reversed().drop(while: { $0.date == today && $0.count == 0 }).prefix { $0.count > 0 }.count
        self.init(
            today: todayCount,
            thisWeek: past.filter { $0.date >= weekStart }.reduce(0) { $0 + $1.count },
            currentStreak: current,
            streakNeedsToday: todayCount == 0 && current > 0,
            longestStreak: past.split { $0.count == 0 }.map(\.count).max() ?? 0)
    }

    /// FR-12: the menu bar's GitHub meters, today's level and the days with contributions in today's week, with the day
    /// boundary and week start of `calendar` as in `init(days:now:calendar:)`.
    public static func menuBarMeters(days: [ContributionDay], now: Date, calendar: Calendar) -> (
        level: Int, activeDays: Int
    ) {
        let today = DayKey(now, calendar: calendar)
        let weekStart = DayKey(calendar.dateInterval(of: .weekOfYear, for: now)!.start, calendar: calendar)
        let week = days.filter { $0.date >= weekStart && $0.date <= today }
        return (week.last { $0.date == today }?.level.rawValue ?? 0, week.filter { $0.count > 0 }.count)
    }
}

/// The calendar as GitHub returns it (FR-18): its weeks start on Sunday, the first and the last one can be short.
public struct ContributionCalendar: Sendable, Codable, Equatable {
    public let login: String
    public let weeks: [[ContributionDay]]
    public let totalContributions: Int

    public init(login: String, weeks: [[ContributionDay]], totalContributions: Int) {
        self.login = login
        self.weeks = weeks
        self.totalContributions = totalContributions
    }

    public var days: [ContributionDay] { Array(weeks.joined()) }
}

public struct GitHubReport: Sendable, Codable {
    public let calendar: ContributionCalendar
    public let stats: ContributionStats

    public init(calendar: ContributionCalendar, stats: ContributionStats) {
        self.calendar = calendar
        self.stats = stats
    }

    /// SPEC §12 GitHub row.
    public static let policy = SchedulePolicy(
        defaultInterval: .seconds(30 * 60), minimumInterval: .seconds(10 * 60), maximumInterval: .seconds(6 * 3600),
        staleAfter: .seconds(2 * 3600), manualFloor: .seconds(30), needsNetwork: true)
}
