import Foundation

/// The neutral outputs of a provider (SPEC §10.1, §10.3, §10.4).

public enum SourceError: Error, Sendable, Equatable {
    case toolNotFound
    case notLoggedIn
    /// The tool runs but its plan exposes no limits; shown as `NotConfiguredReason.unsupportedPlan` (ADR-017).
    case unsupportedPlan(note: String)
    case timedOut
    case processFailed(exitCode: Int32, stderrTail: String)
    case unparseable(rawOutput: String)
    case offline
    case unauthorized
    case rateLimited(until: Date)
    case http(status: Int)
    case decoding(String)
    case io(String)
    /// Escape hatch; every code is documented in its provider's section of SPEC §8.
    case providerSpecific(code: String, message: String)
}

public enum WindowKind: String, Sendable, Codable { case session, weekly, other }

public struct UsageWindow: Equatable, Sendable, Codable {
    /// Verbatim, e.g. "Current session".
    public let label: String
    public let kind: WindowKind
    /// 0...100; can exceed 100 in theory, only the UI clamps.
    public let usedPercent: Double
    /// The output said "<1%".
    public let isBelowOne: Bool
    public let resetsAt: Date?

    public init(label: String, kind: WindowKind, usedPercent: Double, isBelowOne: Bool, resetsAt: Date?) {
        self.label = label
        self.kind = kind
        self.usedPercent = usedPercent
        self.isBelowOne = isBelowOne
        self.resetsAt = resetsAt
    }
}

public struct LimitsReport: Equatable, Sendable, Codable {
    public let provider: ProviderID
    public let windows: [UsageWindow]
    /// Claude Code: the first line of the output.
    public let billingNote: String?
    /// Verbatim tool supplied text (capability `insights`).
    public let insights: String?
    /// For "Show raw output" and diagnostics.
    public let rawOutput: String?

    public init(
        provider: ProviderID, windows: [UsageWindow], billingNote: String?, insights: String?, rawOutput: String?
    ) {
        self.provider = provider
        self.windows = windows
        self.billingNote = billingNote
        self.insights = insights
        self.rawOutput = rawOutput
    }
}

public struct TokenCounts: Equatable, Sendable, Codable {
    public var input, output, cacheWrite, cacheRead: Int
    public var total: Int { input + output + cacheWrite + cacheRead }

    public init(input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }
}

/// A local calendar day, "2026-09-28"; the format makes string order day order.
public struct DayKey: RawRepresentable, Hashable, Comparable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct ActivityDay: Equatable, Sendable, Codable {
    public let day: DayKey
    public var requests: Int
    public var sessions: Int
    public var tokens: TokenCounts
    public var byModel: [String: TokenCounts]

    public init(day: DayKey, requests: Int, sessions: Int, tokens: TokenCounts, byModel: [String: TokenCounts]) {
        self.day = day
        self.requests = requests
        self.sessions = sessions
        self.tokens = tokens
        self.byModel = byModel
    }
}

public struct ActivityReport: Equatable, Sendable, Codable {
    public let provider: ProviderID
    /// Newest last, up to 365.
    public let days: [ActivityDay]
    public let skippedLines: Int

    public init(provider: ProviderID, days: [ActivityDay], skippedLines: Int) {
        self.provider = provider
        self.days = days
        self.skippedLines = skippedLines
    }
}
