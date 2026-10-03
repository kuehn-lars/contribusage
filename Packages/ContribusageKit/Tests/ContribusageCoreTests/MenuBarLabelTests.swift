import ContribusageCore
import Foundation
import Testing

/// FR-12 and SPEC §11.1: the menu bar label's modes, fallbacks, stale and unknown values.

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let enUS = Locale(identifier: "en_US")
/// U+2007: as wide as a digit, so the label keeps the width of three digits (SPEC §11.1).
private let pad = "\u{2007}"

private func descriptor(_ id: String, symbol: String) -> ProviderDescriptor {
    ProviderDescriptor(
        id: ProviderID(rawValue: id), displayName: id, symbolName: symbol, heatmapHue: .orange,
        capabilities: .limits, tokenCategories: [],
        limitsPolicy: SchedulePolicy(
            defaultInterval: .seconds(300), minimumInterval: .seconds(60), maximumInterval: .seconds(3600),
            staleAfter: .seconds(1800), manualFloor: .seconds(60), needsNetwork: true))
}

private func limits(
    _ id: String, symbol: String = "sparkle", age: TimeInterval = 0, _ windows: (WindowKind, Double)...
) -> MenuBarLabel.Provider {
    let report = LimitsReport(
        provider: ProviderID(rawValue: id),
        windows: windows.map {
            UsageWindow(label: "\($0.0)", kind: $0.0, usedPercent: $0.1, isBelowOne: false, resetsAt: now + 3600)
        }, billingNote: nil, insights: nil, rawOutput: nil)
    return (descriptor(id, symbol: symbol), Snapshot(value: report, fetchedAt: now - age, origin: .poll))
}

private func label(
    _ mode: MenuBarMode, provider: String? = nil, _ providers: [MenuBarLabel.Provider],
    github: (today: Int, isStale: Bool)? = nil
) -> MenuBarLabel {
    MenuBarLabel(
        mode: mode, provider: provider.map(ProviderID.init) ?? providers.first?.descriptor.id, providers: providers,
        github: github, at: now,
        locale: enUS)
}

@Test func primaryAndWeeklyShowTheMenuBarProvidersWindow() {
    let claude = limits("a", (.session, 23), (.weekly, 51), (.weekly, 70))
    #expect(label(.primary, [claude]) == MenuBarLabel(symbol: "gauge.with.dots.needle.33percent", text: "23%" + pad))
    #expect(label(.weekly, [claude]) == MenuBarLabel(symbol: "gauge.with.dots.needle.50percent", text: "51%" + pad))
    let other = limits("b", (.session, 5))
    #expect(label(.primary, provider: "b", [claude, other]).text == "5%" + pad + pad)
}

@Test func theGaugeFollowsTheNearestStepAndWarnsFromNinety() {
    func symbol(_ percent: Double) -> String { label(.primary, [limits("a", (.session, percent))]).symbol }
    #expect(symbol(10) == "gauge.with.dots.needle.0percent")
    #expect(symbol(60) == "gauge.with.dots.needle.67percent")
    #expect(symbol(89) == "gauge.with.dots.needle.100percent")
    #expect(symbol(90) == "gauge.open.with.lines.needle.84percent.exclamation")
    #expect(label(.primary, [limits("a", (.session, 100))]).text == "100%")
}

@Test func aMissingWindowFallsBackToTheHighestThenToUnknown() {
    let a = limits("a", symbol: "sparkle", (.weekly, 40))
    let b = limits("b", symbol: "terminal", (.session, 12), (.weekly, 77))
    // `highest` across providers shows the provider's symbol once more than one is on.
    #expect(label(.primary, [a, b]) == MenuBarLabel(symbol: "terminal", text: "77%" + pad))
    #expect(label(.highest, [a]) == MenuBarLabel(symbol: "gauge.with.dots.needle.33percent", text: "40%" + pad))
    // US-1: no probe has succeeded yet.
    let unknown = MenuBarLabel(symbol: "gauge.with.dots.needle.33percent", text: "?" + pad + pad + pad)
    #expect(label(.primary, [(descriptor("a", symbol: "sparkle"), nil)]) == unknown)
    #expect(label(.weekly, [limits("a", (.session, 5))]).text == "5%" + pad + pad)
}

@Test func staleValuesAreMarked() {
    #expect(label(.primary, [limits("a", age: 1801, (.session, 23))]).text == "~23%" + pad)
    #expect(label(.githubToday, [], github: (7, true)).text == "~7")
}

@Test func gitHubModesShowTodaysContributions() {
    let a = limits("a", (.session, 23))
    #expect(label(.githubToday, [a], github: (7, false)) == MenuBarLabel(symbol: "square.grid.3x3.fill", text: "7"))
    #expect(label(.githubToday, [a]).text == "?")
    #expect(label(.primaryAndGitHub, [a], github: (7, false)).text == "23%" + pad + " · 7")
    #expect(
        label(.iconOnly, [a], github: (7, false)) == MenuBarLabel(symbol: "gauge.with.dots.needle.33percent", text: ""))
}

/// FR-12: Settings offers only the modes whose source is on; a saved mode that is not offered shows the first one that
/// is, `iconOnly` with every source off.
@Test func onlyModesOfSourcesThatAreOnAreOffered() {
    #expect(MenuBarMode.offered(providers: true, github: true) == MenuBarMode.allCases)
    #expect(MenuBarMode.offered(providers: true, github: false) == [.primary, .weekly, .highest, .iconOnly])
    #expect(MenuBarMode.offered(providers: false, github: true) == [.githubToday, .iconOnly])
    func resolved(_ mode: MenuBarMode, providers: Bool, github: Bool) -> MenuBarMode {
        mode.resolved(among: MenuBarMode.offered(providers: providers, github: github))
    }
    #expect(resolved(.primaryAndGitHub, providers: true, github: false) == .primary)
    #expect(resolved(.weekly, providers: false, github: true) == .githubToday)
    #expect(resolved(.githubToday, providers: false, github: false) == .iconOnly)
    #expect(resolved(.weekly, providers: true, github: false) == .weekly)
}
