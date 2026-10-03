import Foundation

/// FR-12's display modes, saved under `menuBarMode`.
public enum MenuBarMode: String, Sendable, CaseIterable {
    case primary, weekly, highest, githubToday, primaryAndGitHub, iconOnly

    /// Needs a provider with limits that is on.
    public var usesProviders: Bool { [.primary, .weekly, .highest, .primaryAndGitHub].contains(self) }
    /// Needs GitHub on, and keeps it fetching while shown (FR-46).
    public var usesGitHub: Bool { [.githubToday, .primaryAndGitHub].contains(self) }

    /// The modes whose sources are on (FR-12); `iconOnly` always is.
    public static func offered(providers: Bool, github: Bool) -> [Self] {
        allCases.filter { (providers || !$0.usesProviders) && (github || !$0.usesGitHub) }
    }

    /// The mode the label shows: this one while offered, else the first that is (`iconOnly` with every source off).
    public func resolved(among offered: [Self]) -> Self {
        offered.contains(self) ? self : offered[0]
    }
}

/// What the menu bar item shows (SPEC §11.1): a template SF Symbol and a text, empty for `iconOnly`.
public struct MenuBarLabel: Equatable, Sendable {
    /// An enabled provider and its last limits, if any.
    public typealias Provider = (descriptor: ProviderDescriptor, limits: Snapshot<LimitsReport>?)

    private static let icon = "gauge.with.dots.needle.33percent"

    public let symbol: String
    public let text: String

    public init(symbol: String, text: String) {
        self.symbol = symbol
        self.text = text
    }

    /// `mode` is resolved (`MenuBarMode.resolved`); `providers` are the enabled ones in registry order; `provider` is
    /// the menu bar provider's ID; `github` is `nil` before GitHub's first data.
    public init(
        mode: MenuBarMode, provider: ProviderID?, providers: [Provider], github: (today: Int, isStale: Bool)?,
        at now: Date, locale: Locale = .autoupdatingCurrent
    ) {
        let limits = { (kind: WindowKind?) in
            Self.limits(kind, of: providers.first { $0.descriptor.id == provider }, among: providers, at: now, locale)
        }
        let gitHubText = github.map { ($0.isStale ? "~" : "") + $0.today.formatted(.number.locale(locale)) } ?? "?"
        switch mode {
        case .primary: self = limits(.session)
        case .weekly: self = limits(.weekly)
        case .highest: self = limits(nil)
        case .githubToday: self.init(symbol: "square.grid.3x3.fill", text: gitHubText)
        case .primaryAndGitHub:
            let primary = limits(.session)
            self.init(symbol: primary.symbol, text: primary.text + " · " + gitHubText)
        case .iconOnly: self.init(symbol: Self.icon, text: "")
        }
    }

    /// The provider's first window of `kind`, else the highest window across providers, else `?` (FR-12, US-1).
    private static func limits(
        _ kind: WindowKind?, of provider: Provider?, among providers: [Provider], at now: Date, _ locale: Locale
    ) -> Self {
        if let kind, let provider, let window = provider.limits?.value.windows.first(where: { $0.kind == kind }) {
            return Self(window, of: provider, symbol: nil, at: now, locale: locale)
        }
        // A reset window's value is unknown (FR-11), so it never counts.
        let highest = providers.flatMap { provider in
            (provider.limits?.value.windows ?? []).map { (window: $0, provider: provider) }
        }
        .filter { !$0.window.isReset(at: now) }.max { $0.window.usedPercent < $1.window.usedPercent }
        guard let highest else { return Self(symbol: icon, text: padded("?")) }
        // SPEC §11.1: with more than one provider the provider's symbol tells whose window it is.
        let symbol = providers.count > 1 ? highest.provider.descriptor.symbolName : nil
        return Self(highest.window, of: highest.provider, symbol: symbol, at: now, locale: locale)
    }

    /// A window as `~23%`; the gauge follows its percentage unless `symbol` replaces it.
    private init(_ window: UsageWindow, of provider: Provider, symbol: String?, at now: Date, locale: Locale) {
        let stale = provider.descriptor.limitsPolicy.flatMap { provider.limits?.isStale(at: now, after: $0.staleAfter) }
        let text = (stale == true ? "~" : "") + window.percentText(at: now, locale: locale)
        self.init(symbol: symbol ?? Self.gauge(window, at: now), text: Self.padded(text))
    }

    /// The nearest of the 0/33/50/67/100 % variants; a warning gauge from 90 % (SPEC §11.1).
    private static func gauge(_ window: UsageWindow, at now: Date) -> String {
        if window.isReset(at: now) { return icon }
        if window.usedPercent >= 90 { return "gauge.open.with.lines.needle.84percent.exclamation" }
        let step = [0, 33, 50, 67, 100].min {
            abs(Double($0) - window.usedPercent) < abs(Double($1) - window.usedPercent)
        }!
        return "gauge.with.dots.needle.\(step)percent"
    }

    /// SPEC §11.1 stable width: figure spaces (as wide as a digit) up to three digits.
    // ponytail: `~` and `<` still widen the label by a few points; measure the text if that jitter shows.
    private static func padded(_ text: String) -> String {
        text + String(repeating: "\u{2007}", count: max(0, 3 - text.filter(\.isNumber).count))
    }
}
