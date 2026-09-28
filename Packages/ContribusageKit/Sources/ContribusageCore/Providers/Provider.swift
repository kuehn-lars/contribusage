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

    public init(
        defaultInterval: Duration, minimumInterval: Duration, maximumInterval: Duration, staleAfter: Duration,
        manualFloor: Duration
    ) {
        self.defaultInterval = defaultInterval
        self.minimumInterval = minimumInterval
        self.maximumInterval = maximumInterval
        self.staleAfter = staleAfter
        self.manualFloor = manualFloor
    }
}

public struct ProviderDescriptor: Sendable {
    public let id: ProviderID
    /// "Claude Code".
    public let displayName: String
    /// A neutral SF Symbol, never a vendor logo.
    public let symbolName: String
    public let capabilities: ProviderCapabilities
    /// Categories the UI shows; the others stay 0 and are hidden (SPEC §10.4).
    public let tokenCategories: Set<TokenCategory>
    /// `nil` if limits are push only or absent.
    public let limitsPolicy: SchedulePolicy?

    public init(
        id: ProviderID, displayName: String, symbolName: String, capabilities: ProviderCapabilities,
        tokenCategories: Set<TokenCategory>, limitsPolicy: SchedulePolicy?
    ) {
        self.id = id
        self.displayName = displayName
        self.symbolName = symbolName
        self.capabilities = capabilities
        self.tokenCategories = tokenCategories
        self.limitsPolicy = limitsPolicy
    }
}

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
