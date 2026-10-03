/// The provider contract of SPEC §7.3 and §10.2. Everything outside a provider works only with these types.

public struct ProviderCapabilities: OptionSet, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let limits = ProviderCapabilities(rawValue: 1 << 0)
    public static let activity = ProviderCapabilities(rawValue: 1 << 1)
    public static let insights = ProviderCapabilities(rawValue: 1 << 2)
}

public enum TokenCategory: String, Sendable, Codable, CaseIterable {
    case input, output, cacheWrite, cacheRead
}

public struct SchedulePolicy: Sendable, Equatable {
    public let defaultInterval: Duration
    public let minimumInterval: Duration
    public let maximumInterval: Duration
    public let staleAfter: Duration
    public let manualFloor: Duration
    /// Skipped while offline (SPEC §12 rule 2).
    public let needsNetwork: Bool

    public init(
        defaultInterval: Duration, minimumInterval: Duration, maximumInterval: Duration, staleAfter: Duration,
        manualFloor: Duration, needsNetwork: Bool
    ) {
        self.defaultInterval = defaultInterval
        self.minimumInterval = minimumInterval
        self.maximumInterval = maximumInterval
        self.staleAfter = staleAfter
        self.manualFloor = manualFloor
        self.needsNetwork = needsNetwork
    }
}

public struct ProviderDescriptor: Sendable {
    public let id: ProviderID
    /// "Claude Code".
    public let displayName: String
    /// A neutral SF Symbol, never a vendor logo.
    public let symbolName: String
    /// Its heatmap layer's color (FR-48, SPEC §11.4).
    public let heatmapHue: HeatmapHue
    public let capabilities: ProviderCapabilities
    /// Categories the UI shows; the others stay 0 and are hidden (SPEC §10.4).
    public let tokenCategories: Set<TokenCategory>
    /// `nil` if limits are push only or absent.
    public let limitsPolicy: SchedulePolicy?
    /// A text the tool printed (a window label, an insights period or summary) as the UI shows it, in the app's
    /// language (NFR-10); the printed text stays the key.
    public let toolText: @Sendable (String) -> String

    public init(
        id: ProviderID, displayName: String, symbolName: String, heatmapHue: HeatmapHue,
        capabilities: ProviderCapabilities,
        tokenCategories: Set<TokenCategory>, limitsPolicy: SchedulePolicy?,
        toolText: @escaping @Sendable (String) -> String = { $0 }
    ) {
        self.id = id
        self.displayName = displayName
        self.symbolName = symbolName
        self.heatmapHue = heatmapHue
        self.capabilities = capabilities
        self.tokenCategories = tokenCategories
        self.limitsPolicy = limitsPolicy
        self.toolText = toolText
    }
}

/// Named system hues; the app maps them to colors. Green is GitHub's and red means critical, so neither is a provider's
/// (SPEC §11.4, ADR-032).
public enum HeatmapHue: String, Sendable, Codable { case orange, blue, purple, teal, pink, indigo }

/// FR-3.
public enum ProviderAvailability: Sendable, Equatable {
    case available(version: String)
    case notInstalled
    case notSignedIn
    case unsupportedPlan(note: String)
    case unknown(reason: String)
}

public protocol UsageProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    /// Cheap and side effect free; `ProviderRegistry` limits how often it runs.
    func detectAvailability() async -> ProviderAvailability
    var limits: (any LimitsSource)? { get }
    var activity: (any ActivitySource)? { get }
    /// Provider specific lines for "Copy diagnostics" (FR-36). May run detection, never a fetch; never holds a secret.
    func diagnostics() async -> [String]
}

extension UsageProvider {
    public func diagnostics() async -> [String] { [] }
}

/// Failures are thrown as `SourceError`; cancellation as `CancellationError`.
public protocol LimitsSource: Sendable {
    /// Polled refresh (for Claude Code: one probe). Must honour cancellation.
    func fetch() async throws -> LimitsReport
    /// Updates the source pushes on its own (for Claude Code: the status line bridge). An empty stream if none.
    func pushedUpdates() -> AsyncStream<LimitsReport>
}

/// Watching runs exactly as long as a `reports()` stream is consumed (ADR-016).
public protocol ActivitySource: Sendable {
    /// Starts watching, emits an initial report, then one per change. Cancelling the consumer stops the watching and
    /// releases every file handle.
    func reports() -> AsyncStream<ActivityReport>
    /// Re-reads everything (on wake or popover open); the result arrives on the open `reports()` streams.
    func rescan() async
}
