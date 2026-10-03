import ContribusageCore
import Foundation
import os

/// Shaped unlike Claude Code on purpose (SPEC §16.4): one `weekly` window, limits only pushed (no `limitsPolicy`),
/// token categories `input` and `output` only.
public final class FakeProvider: UsageProvider {
    public let descriptor: ProviderDescriptor
    public let limits: (any LimitsSource)?
    public let activity: (any ActivitySource)?
    private let state: OSAllocatedUnfairLock<(availability: ProviderAvailability, detections: Int)>

    /// `fetch` defaults to failing: a push-only source has nothing to poll. The activity source reads `reads` through
    /// `fileReader` before each report.
    public init(
        id: ProviderID = .fake,
        availability: ProviderAvailability = .available(version: "1.0"),
        fileEvents: FakeFileEvents = FakeFileEvents(),
        fileReader: FakeFileReader = FakeFileReader(),
        reads: [URL] = [],
        fetch: @escaping @Sendable () async throws -> LimitsReport = {
            throw SourceError.providerSpecific(code: "push-only", message: "limits are only pushed")
        }
    ) {
        descriptor = ProviderDescriptor(
            id: id, displayName: "Fake Tool", symbolName: "hammer", heatmapHue: .blue,
            capabilities: [.limits, .activity],
            tokenCategories: [.input, .output], limitsPolicy: nil
        )
        limits = FakeLimitsSource(id: id, fetch: fetch)
        activity = FakeActivitySource(id: id, fileEvents: fileEvents, fileReader: fileReader, reads: reads)
        state = .init(initialState: (availability, 0))
    }

    /// What the next detection reports.
    public var availability: ProviderAvailability {
        get { state.withLock { $0.availability } }
        set { state.withLock { $0.availability = newValue } }
    }

    public var detections: Int { state.withLock { $0.detections } }

    public func detectAvailability() async -> ProviderAvailability {
        state.withLock {
            $0.detections += 1
            return $0.availability
        }
    }
}

private struct FakeLimitsSource: LimitsSource {
    let id: ProviderID
    let fetch: @Sendable () async throws -> LimitsReport

    func fetch() async throws -> LimitsReport { try await fetch() }

    /// Pushes the current report on subscription, as a bridge pushes its file's current content.
    func pushedUpdates() -> AsyncStream<LimitsReport> {
        let window = UsageWindow(
            label: "This week", kind: .weekly, usedPercent: 42, isBelowOne: false, resetsAt: nil
        )
        let report = LimitsReport(provider: id, windows: [window], billingNote: nil, insights: nil, rawOutput: nil)
        return AsyncStream { $0.yield(report) }
    }
}

/// One report on start, one per `FakeFileEvents.send(_:)`.
private struct FakeActivitySource: ActivitySource {
    let id: ProviderID
    let fileEvents: FakeFileEvents
    let fileReader: FakeFileReader
    let reads: [URL]

    func reports() -> AsyncStream<ActivityReport> {
        for url in reads { _ = try? fileReader.contents(of: url) }
        let day = ActivityDay(
            day: DayKey(rawValue: "2026-09-28"), requests: 3, sessions: 1,
            tokens: TokenCounts(input: 120, output: 80), byModel: [:]
        )
        let report = ActivityReport(provider: id, days: [day], skippedLines: 0)
        let changes = fileEvents.changes(in: [URL(filePath: "/tmp/fake-tool")], debounce: .seconds(1))
        return AsyncStream { continuation in
            continuation.yield(report)
            let watching = Task {
                for await _ in changes { continuation.yield(report) }
                continuation.finish()
            }
            continuation.onTermination = { _ in watching.cancel() }
        }
    }

    /// Nothing to re-read: the report is fixed.
    func rescan() async {}
}
