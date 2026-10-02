import Foundation

/// Everything the UI shows is a snapshot (SPEC §5, §10.1).
public struct Snapshot<Value: Sendable & Codable>: Sendable, Codable {
    public let value: Value
    public let fetchedAt: Date
    public let origin: Origin

    public init(value: Value, fetchedAt: Date, origin: Origin) {
        self.value = value
        self.fetchedAt = fetchedAt
        self.origin = origin
    }

    /// SPEC §12 "stale after".
    public func isStale(at now: Date, after limit: Duration) -> Bool {
        now.timeIntervalSince(fetchedAt) > limit.timeInterval
    }
}

extension Snapshot: Equatable where Value: Equatable {}

/// Open set of origins; providers add their own constants.
public struct Origin: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let cache = Origin(rawValue: "cache")
    /// A limits source's `fetch()`, run by `RefreshCoordinator`.
    public static let poll = Origin(rawValue: "poll")
    /// An activity source's `reports()`.
    public static let activity = Origin(rawValue: "activity")
    public static let github = Origin(rawValue: "github")
}

public enum SourceState<Value: Sendable & Codable>: Sendable {
    case notConfigured(NotConfiguredReason)
    case loading(previous: Snapshot<Value>?)
    case loaded(Snapshot<Value>)
    case failed(SourceError, previous: Snapshot<Value>?)

    /// The values the UI can show, current or previous (SPEC §11.3).
    public var snapshot: Snapshot<Value>? {
        switch self {
        case .notConfigured: nil
        case .loading(let previous), .failed(_, let previous): previous
        case .loaded(let snapshot): snapshot
        }
    }

    /// One line for "Copy diagnostics" (FR-36): the case, the error in full and when the shown values were fetched.
    public var diagnostics: String {
        let state =
            switch self {
            case .notConfigured(let reason): "not configured: \(reason)"
            case .loading: "loading"
            case .loaded: "loaded"
            case .failed(let error, _): "failed: \(error)"
            }
        return snapshot.map { "\(state), fetched \($0.fetchedAt.formatted(.iso8601))" } ?? state
    }
}

public enum NotConfiguredReason: Sendable, Equatable {
    case providerDisabled
    case toolNotInstalled
    case unsupportedPlan(note: String)
    case noLocalData
    case githubTokenMissing
}
