import ContribusageCore
import Foundation

/// Folds decoded transcript lines into per-day, per-model totals (SPEC §8.3.3, FR-24, FR-25).
public struct TranscriptAggregator: Sendable {
    /// Lines with neither `message.id` nor `requestId`: counted as requests, surfaced in diagnostics.
    public private(set) var linesWithoutKey = 0

    private let calendar: Calendar
    private var seen: Set<String> = []
    private var buckets: [DayKey: Bucket] = [:]

    private struct Bucket {
        var requests = 0
        var sessions: Set<String> = []
        var tokens = TokenCounts()
        var byModel: [String: TokenCounts] = [:]

        mutating func add(_ line: TranscriptLine) {
            let counts = TokenCounts(
                input: line.input, output: line.output, cacheWrite: line.cacheWrite, cacheRead: line.cacheRead)
            requests += 1
            if let session = line.sessionID { sessions.insert(session) }
            tokens += counts
            byModel[line.model, default: TokenCounts()] += counts
        }
    }

    /// `calendar` defines the local day (the Mac's current zone in the app).
    public init(calendar: Calendar = .current) { self.calendar = calendar }

    public mutating func add(_ line: TranscriptLine) { add(line, key: line.key) }

    /// `key` in place of `line.key`, for a caller that keeps the key apart from the line.
    public mutating func add(_ line: TranscriptLine, key: String?) {
        if let key {
            guard seen.insert(key).inserted else { return }
        } else {
            linesWithoutKey += 1
        }
        buckets[DayKey(line.timestamp, calendar: calendar), default: Bucket()].add(line)
    }

    /// Oldest first.
    public func days() -> [ActivityDay] {
        buckets.sorted { $0.key < $1.key }.map { day, bucket in
            ActivityDay(
                day: day, requests: bucket.requests, sessions: bucket.sessions.count, tokens: bucket.tokens,
                byModel: bucket.byModel)
        }
    }
}
