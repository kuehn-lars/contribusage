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

/// FR-51: how the label draws its value; saved under `menuBarStyle`.
public enum MenuBarStyle: String, Sendable, CaseIterable {
    /// The app's mark: a prompt whose code lines fill as the window is used.
    case prompt
    /// The shown window outside, the provider's other window inside.
    case rings
    /// One ring with the number inside, no text.
    case ring
    /// A prompt and a cursor line that fills.
    case line
    /// The source's last three weeks of activity.
    case heatmap
    /// The shared heatmap's layers over the last three weeks, a stripe per active layer in each day (FR-49).
    case sharedHeatmap
    /// The source's name and the value.
    case text
}

/// FR-51: the label's color; saved under `menuBarTint`, a custom color as hex under `menuBarColor`.
public enum MenuBarTint: String, Sendable, CaseIterable {
    case provider, usage, accent, monochrome, custom
}

/// What the menu bar item shows (SPEC §11.1); the app draws it in the chosen style and tint (FR-51).
public struct MenuBarLabel: Equatable, Sendable {
    /// An enabled provider and its last limits, if any.
    public typealias Provider = (descriptor: ProviderDescriptor, limits: Snapshot<LimitsReport>?)

    /// `23%` with figure spaces in front up to two digits, `?`, today's contributions, or empty for `iconOnly`.
    public var text: String
    /// The source's name, for the text style and VoiceOver; the app's name with every source off.
    public var title: String
    /// The shown window's used fraction, 0 to 1; `nil` without a window or while it is reset (FR-11). For GitHub, today's
    /// contribution level of 4.
    public var meter: Double?
    /// The same provider's other window (weekly beside session, session beside weekly), for the rings style. For
    /// GitHub, the days with contributions this week of 7.
    public var companion: Double?
    public var isStale = false
    /// The provider's symbol when `highest` chose among more than one provider (SPEC §7.7).
    public var badge: String?
    /// Whose activity the heatmap style draws.
    public var source: BlockID?

    public init(
        text: String, title: String, meter: Double? = nil, companion: Double? = nil, isStale: Bool = false,
        badge: String? = nil, source: BlockID? = nil
    ) {
        self.text = text
        self.title = title
        self.meter = meter
        self.companion = companion
        self.isStale = isStale
        self.badge = badge
        self.source = source
    }

    /// `mode` is resolved (`MenuBarMode.resolved`); `providers` are the enabled ones in registry order; `provider` is
    /// the menu bar provider's ID; `github` is `nil` before GitHub's first data, its `level` today's (0 to 4) and
    /// `activeDays` this week's days with contributions.
    public init(
        mode: MenuBarMode, provider: ProviderID?, providers: [Provider],
        github: (today: Int, level: Int, activeDays: Int, isStale: Bool)?,
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
        case .githubToday:
            self.init(
                text: gitHubText, title: "GitHub", meter: github.map { Double($0.level) / 4 },
                companion: github.map { Double($0.activeDays) / 7 }, isStale: github?.isStale ?? false,
                source: .github)
        case .primaryAndGitHub:
            self = limits(.session)
            text += " · " + gitHubText
        case .iconOnly:
            self = providers.isEmpty ? Self(text: "", title: "contribusage") : limits(.session)
            text = ""
        }
    }

    /// The provider's first window of `kind`, else the highest window across providers, else `?` (FR-12, US-1).
    private static func limits(
        _ kind: WindowKind?, of provider: Provider?, among providers: [Provider], at now: Date, _ locale: Locale
    ) -> Self {
        if let kind, let provider, let window = provider.limits?.value.windows.first(where: { $0.kind == kind }) {
            return Self(window, of: provider, badge: nil, at: now, locale: locale)
        }
        // A reset window's value is unknown (FR-11), so it never counts.
        let highest = providers.flatMap { provider in
            (provider.limits?.value.windows ?? []).map { (window: $0, provider: provider) }
        }
        .filter { !$0.window.isReset(at: now) }.max { $0.window.usedPercent < $1.window.usedPercent }
        guard let highest else {
            let shown = provider ?? providers.first
            return Self(
                text: padded("?"), title: shown?.descriptor.displayName ?? "contribusage",
                source: shown.map { .provider($0.descriptor.id) })
        }
        // SPEC §7.7: with more than one provider the provider's symbol tells whose window it is.
        let badge = providers.count > 1 ? highest.provider.descriptor.symbolName : nil
        return Self(highest.window, of: highest.provider, badge: badge, at: now, locale: locale)
    }

    /// A window as `~23%`, with its provider's other window as the companion.
    private init(_ window: UsageWindow, of provider: Provider, badge: String?, at now: Date, locale: Locale) {
        let stale = provider.descriptor.limitsPolicy.flatMap { provider.limits?.isStale(at: now, after: $0.staleAfter) }
        let windows = provider.limits?.value.windows ?? []
        let other = windows.first { $0.kind == (window.kind == .weekly ? .session : .weekly) && $0 != window }
        self.init(
            text: Self.padded((stale == true ? "~" : "") + window.percentText(at: now, locale: locale)),
            title: provider.descriptor.displayName, meter: Self.fraction(window, at: now),
            companion: other.flatMap { Self.fraction($0, at: now) }, isStale: stale == true, badge: badge,
            source: .provider(provider.descriptor.id))
    }

    private static func fraction(_ window: UsageWindow, at now: Date) -> Double? {
        window.isReset(at: now) ? nil : min(max(window.usedPercent / 100, 0), 1)
    }

    /// SPEC §11.1 stable width: figure spaces (as wide as a digit) in front up to two digits, so the label ends at its
    /// value; `100%` widens it by one digit.
    // ponytail: `~` and `<` still widen the label by a few points; measure the text if that jitter shows.
    private static func padded(_ text: String) -> String {
        String(repeating: "\u{2007}", count: max(0, 2 - text.filter(\.isNumber).count)) + text
    }
}
