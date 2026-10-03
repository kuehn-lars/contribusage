import ContribusageCore
import Foundation
import Testing

/// FR-12 and SPEC §11.1: the menu bar label's modes, fallbacks, stale and unknown values.

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let enUS = Locale(identifier: "en_US")
/// U+2007: as wide as a digit, so the label keeps the width of three digits (SPEC §11.1).
private let pad = "\u{2007}"
private let a = ProviderID(rawValue: "a")
private let b = ProviderID(rawValue: "b")

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
    #expect(
        label(.primary, [claude])
            == MenuBarLabel(text: "23%" + pad, title: "a", meter: 0.23, companion: 0.51, source: .provider(a)))
    #expect(
        label(.weekly, [claude])
            == MenuBarLabel(text: "51%" + pad, title: "a", meter: 0.51, companion: 0.23, source: .provider(a)))
    let other = limits("b", (.session, 5))
    #expect(label(.primary, provider: "b", [claude, other]).text == "5%" + pad + pad)
    #expect(label(.primary, provider: "b", [claude, other]).companion == nil)
    #expect(label(.primary, [limits("a", (.session, 100))]).text == "100%")
}

/// FR-11: a reset window's value is unknown, so it fills nothing.
@Test func aResetWindowFillsNothing() {
    let report = LimitsReport(
        provider: a,
        windows: [UsageWindow(label: "s", kind: .session, usedPercent: 80, isBelowOne: false, resetsAt: now - 1)],
        billingNote: nil, insights: nil, rawOutput: nil)
    let shown = label(
        .primary, [(descriptor("a", symbol: "sparkle"), Snapshot(value: report, fetchedAt: now, origin: .poll))])
    #expect(shown.meter == nil)
}

@Test func aMissingWindowFallsBackToTheHighestThenToUnknown() {
    let first = limits("a", symbol: "sparkle", (.weekly, 40))
    let second = limits("b", symbol: "terminal", (.session, 12), (.weekly, 77))
    // `highest` across providers shows the provider's symbol once more than one is on (SPEC §7.7).
    #expect(
        label(.primary, [first, second])
            == MenuBarLabel(
                text: "77%" + pad, title: "b", meter: 0.77, companion: 0.12, badge: "terminal", source: .provider(b)))
    #expect(label(.highest, [first]).badge == nil)
    // US-1: no probe has succeeded yet.
    #expect(
        label(.primary, [(descriptor("a", symbol: "sparkle"), nil)])
            == MenuBarLabel(text: "?" + pad + pad + pad, title: "a", source: .provider(a)))
    #expect(label(.weekly, [limits("a", (.session, 5))]).text == "5%" + pad + pad)
}

@Test func staleValuesAreMarked() {
    let stale = label(.primary, [limits("a", age: 1801, (.session, 23))])
    #expect(stale.text == "~23%" + pad)
    #expect(stale.isStale)
    #expect(label(.githubToday, [], github: (7, true)).text == "~7")
    #expect(label(.githubToday, [], github: (7, true)).isStale)
}

@Test func gitHubModesShowTodaysContributions() {
    let first = limits("a", (.session, 23))
    #expect(
        label(.githubToday, [first], github: (7, false)) == MenuBarLabel(text: "7", title: "GitHub", source: .github))
    #expect(label(.githubToday, [first]).text == "?")
    let both = label(.primaryAndGitHub, [first], github: (7, false))
    #expect(both.text == "23%" + pad + " · 7")
    #expect(both.meter == 0.23)
}

/// `iconOnly` keeps the primary meter and drops the text; with every source off it names the app.
@Test func iconOnlyKeepsTheMeter() {
    #expect(
        label(.iconOnly, [limits("a", (.session, 23))], github: (7, false))
            == MenuBarLabel(text: "", title: "a", meter: 0.23, source: .provider(a)))
    #expect(label(.iconOnly, []) == MenuBarLabel(text: "", title: "contribusage"))
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
