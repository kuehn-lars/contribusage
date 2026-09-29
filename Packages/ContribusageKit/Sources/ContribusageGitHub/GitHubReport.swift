import ContribusageCore

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
}

/// The calendar as GitHub returns it (FR-18).
public struct ContributionCalendar: Sendable, Codable, Equatable {
    public let login: String
    public let days: [ContributionDay]
    public let totalContributions: Int

    public init(login: String, days: [ContributionDay], totalContributions: Int) {
        self.login = login
        self.days = days
        self.totalContributions = totalContributions
    }
}

public struct GitHubReport: Sendable, Codable {
    public let calendar: ContributionCalendar
    public let stats: ContributionStats

    public init(calendar: ContributionCalendar, stats: ContributionStats) {
        self.calendar = calendar
        self.stats = stats
    }

    /// SPEC §12.
    public static let staleAfter: Duration = .seconds(2 * 3600)
}
