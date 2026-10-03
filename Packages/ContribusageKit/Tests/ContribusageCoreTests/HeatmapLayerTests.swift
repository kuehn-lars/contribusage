import ContribusageCore
import Foundation
import Testing

/// SPEC §16.3 heatmap levels, layer order and the FR-49 line (FR-48, FR-49, §10.8).

private let a = ProviderID(rawValue: "a")
private let b = ProviderID(rawValue: "b")
private let enUS = Locale(identifier: "en_US")
private func day(_ n: Int) -> DayKey { DayKey(rawValue: "2026-09-\(10 + n)") }

/// FR-48: 0 for a day without tokens, otherwise the quartile among the non-zero days; the busiest day reaches 4.
@Test func providerLevelsAreQuartilesOfTheNonZeroDays() {
    let layer = HeatmapLayer.quartiled(
        .provider(a), name: "A", values: [day(0): 0, day(1): 10, day(2): 20, day(3): 30, day(4): 40])
    #expect(layer.levels == [day(0): 0, day(1): 1, day(2): 2, day(3): 3, day(4): 4])
    #expect(layer.values[day(1)] == 10)
}

@Test func oneActiveDayIsLevelFourAndAllZeroDaysAreLevelZero() {
    #expect(
        HeatmapLayer.quartiled(.provider(a), name: "A", values: [day(0): 0, day(1): 5]).levels == [
            day(0): 0, day(1): 4,
        ])
    #expect(
        HeatmapLayer.quartiled(.provider(a), name: "A", values: [day(0): 0, day(1): 0]).levels == [
            day(0): 0, day(1): 0,
        ])
}

/// FR-48: a day without data has no level, so it is drawn like 0, and reads "no data" (FR-49).
@Test func daysWithoutDataHaveNoLevelAndReadNoData() {
    let layer = HeatmapLayer.quartiled(.provider(a), name: "A", values: [day(1): 5])
    #expect(layer.levels[day(0)] == nil)
    #expect(layer.text(on: day(0), locale: enUS) == "no data")
}

/// FR-20: GitHub's `contributionLevel` is passed through unchanged.
@Test func gitHubLevelsArePassedThrough() {
    let layer = HeatmapLayer(
        id: .github, name: "GitHub", values: [day(0): 1, day(1): 100], levels: [day(0): 4, day(1): 1])
    #expect(layer.levels == [day(0): 4, day(1): 1])
}

/// FR-48, FR-49: one layer per source that is on, in the heatmap and has daily data, in block order; hiding a block
/// keeps its layer.
@Test func layersFollowBlockOrder() {
    var layout = PopoverLayout()
    layout.order = [.github, .heatmap, .provider(b), .provider(a)]
    layout.hiddenBlocks = [.github]
    let on: Set<BlockID> = [.provider(a), .provider(b), .github]
    #expect(layout.heatmapLayers(sources: [a, b], on: on) == [.github, .provider(b), .provider(a)])
    layout.outOfHeatmap = [.provider(b)]
    #expect(layout.heatmapLayers(sources: [a], on: on.subtracting([.github])) == [.provider(a)])
}

/// FR-49: the day, then every layer in order; tokens compact, contributions counted, a missing day "no data".
@Test func theDayLineReadsEveryLayer() {
    let tokens = HeatmapLayer.quartiled(.provider(a), name: "Claude Code", values: [day(0): 1_200_000])
    let github = HeatmapLayer(id: .github, name: "GitHub", values: [day(0): 5], levels: [day(0): 2])
    #expect(
        HeatmapLayer.line(day(0), layers: [tokens, github], locale: enUS)
            == "2026-09-10 · Claude Code: 1.2M tokens · GitHub: 5 contributions")
    #expect(github.text(1, locale: enUS) == "1 contribution")
    #expect(
        HeatmapLayer.line(day(1), layers: [tokens, github], locale: enUS)
            == "2026-09-11 · Claude Code: no data · GitHub: no data")
}

/// FR-20, FR-48: 26 week columns starting on a Sunday, the last ending today.
@Test func theRangeIsTwentySixWeeksEndingToday() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
    let wednesday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12)))
    let days = HeatmapLayer.days(through: wednesday, calendar: calendar)
    #expect(days.count == 25 * 7 + 4)
    #expect(days.last == DayKey(rawValue: "2026-09-30"))
    #expect(days.first == DayKey(rawValue: "2026-04-05"))  // a Sunday
}
