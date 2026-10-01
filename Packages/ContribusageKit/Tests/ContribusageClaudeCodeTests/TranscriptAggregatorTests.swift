import ContribusageCore
import Foundation
import Testing

@testable import ContribusageClaudeCode

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func line(
    _ stamp: String, session: String? = "s1", request: String? = "r1", message: String? = "m1",
    model: String = "opus", input: Int = 1, output: Int = 2, write: Int = 3, read: Int = 4
) throws -> TranscriptLine {
    TranscriptLine(
        timestamp: try Date(stamp, strategy: .iso8601), sessionID: session, requestID: request, messageID: message,
        model: model, isSidechain: false, input: input, output: output, cacheWrite: write, cacheRead: read)
}

/// SPEC 8.3.3: one response written as several lines counts once.
@Test func duplicateKeyCountsOnce() throws {
    var aggregator = TranscriptAggregator(calendar: utc)
    try aggregator.add(line("2026-09-27T10:00:00Z"))
    try aggregator.add(line("2026-09-27T10:00:01Z"))
    let day = try #require(aggregator.days().first)
    #expect(day.requests == 1)
    #expect(day.tokens == TokenCounts(input: 1, output: 2, cacheWrite: 3, cacheRead: 4))
}

@Test func keyFallsBackToMessageIDThenCountsAndFlags() throws {
    var aggregator = TranscriptAggregator(calendar: utc)
    try aggregator.add(line("2026-09-27T10:00:00Z", request: nil, message: "m1"))
    try aggregator.add(line("2026-09-27T10:00:01Z", request: nil, message: "m1"))
    #expect(aggregator.linesWithoutKey == 0)
    try aggregator.add(line("2026-09-27T10:00:02Z", request: nil, message: nil))
    try aggregator.add(line("2026-09-27T10:00:03Z", request: nil, message: nil))
    #expect(aggregator.linesWithoutKey == 2)
    #expect(aggregator.days().first?.requests == 3)
}

@Test func sessionsAreUniquePerDayAndModelsSplit() throws {
    var aggregator = TranscriptAggregator(calendar: utc)
    try aggregator.add(line("2026-09-27T10:00:00Z", request: "a", model: "opus"))
    try aggregator.add(line("2026-09-27T11:00:00Z", request: "b", model: "haiku"))
    try aggregator.add(line("2026-09-28T11:00:00Z", request: "c", model: "opus"))
    let days = aggregator.days()
    #expect(days.map(\.day.rawValue) == ["2026-09-27", "2026-09-28"])
    #expect(days.map(\.sessions) == [1, 1])
    #expect(days[0].requests == 2 && days[0].byModel.keys.sorted() == ["haiku", "opus"])
    #expect(days[0].tokens.input == 2 && days[0].byModel["opus"]?.output == 2)
}

@Test func dayUsesTheCalendarZone() throws {
    var tokyo = utc
    tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    var aggregator = TranscriptAggregator(calendar: tokyo)
    try aggregator.add(line("2026-09-27T20:00:00Z"))
    #expect(aggregator.days().first?.day.rawValue == "2026-09-28")
}
