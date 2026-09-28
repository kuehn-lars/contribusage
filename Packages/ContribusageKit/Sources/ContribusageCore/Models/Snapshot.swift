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
        now.timeIntervalSince(fetchedAt) > Double(limit.components.seconds)
    }
}

extension Snapshot: Equatable where Value: Equatable {}

/// Open set of origins; providers add their own constants.
public struct Origin: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let cache = Origin(rawValue: "cache")
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
}

public enum NotConfiguredReason: Sendable, Equatable {
    case providerDisabled
    case toolNotInstalled
    case unsupportedPlan(note: String)
    case noLocalData
    case githubTokenMissing
}
