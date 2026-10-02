import AppKit
import ContribusageCore
import Foundation
import Testing
import os

/// The shared checks of SPEC §16.4, run from every provider's test target against the provider wired to fakes.
/// Violations are recorded as test issues at the caller's line.
///
/// Not checked here: "no HTTP" holds by construction (a provider receives no `HTTPTransport`); "no reads outside the
/// declared roots" needs a file system seam, which comes with T-4.7 (ADR-025).
public enum ProviderConformance {
    /// - Parameters:
    ///   - provider: wired to fakes that answer normally.
    ///   - neverFinishing: wired so `limits.fetch()` never finishes. Required when the provider has limits.
    ///   - failing: wired so `limits.fetch()` fails. Required when the provider has limits.
    ///   - fileEvents: the fake the activity source watches through. Required when the provider has activity.
    public static func check(
        _ provider: any UsageProvider,
        neverFinishing: (any UsageProvider)? = nil,
        failing: (any UsageProvider)? = nil,
        fileEvents: FakeFileEvents? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        checkDescriptor(of: provider, at: sourceLocation)
        if let limits = provider.limits {
            await checkLimits(
                limits, of: provider.descriptor.id, neverFinishing: neverFinishing?.limits, failing: failing?.limits,
                at: sourceLocation
            )
        }
        if let activity = provider.activity {
            await checkActivity(activity, of: provider.descriptor.id, fileEvents: fileEvents, at: sourceLocation)
        }
    }

    private static func checkDescriptor(of provider: any UsageProvider, at location: SourceLocation) {
        let descriptor = provider.descriptor
        #expect(descriptor.id.rawValue.wholeMatch(of: /[a-z0-9-]+/) != nil, "invalid ID", sourceLocation: location)
        #expect(!descriptor.displayName.isEmpty, sourceLocation: location)
        #expect(
            NSImage(systemSymbolName: descriptor.symbolName, accessibilityDescription: nil) != nil,
            "unknown SF Symbol \(descriptor.symbolName)", sourceLocation: location
        )
        #expect(descriptor.capabilities.contains(.limits) == (provider.limits != nil), sourceLocation: location)
        #expect(descriptor.capabilities.contains(.activity) == (provider.activity != nil), sourceLocation: location)
    }

    private static func checkLimits(
        _ limits: any LimitsSource, of id: ProviderID, neverFinishing: (any LimitsSource)?,
        failing: (any LimitsSource)?, at location: SourceLocation
    ) async {
        func checkReport(_ report: LimitsReport) {
            #expect(report.provider == id, sourceLocation: location)
            for window in report.windows {
                #expect(
                    window.usedPercent.isFinite && window.usedPercent >= 0, "\(window.label): \(window.usedPercent)",
                    sourceLocation: location
                )
            }
        }
        func checkFailure(_ error: any Error) {
            #expect(error is SourceError, "untyped error \(error)", sourceLocation: location)
        }

        do { checkReport(try await limits.fetch()) } catch { checkFailure(error) }
        let pushed = limits.pushedUpdates()
        if let report = await withTimeout(.seconds(2), { await pushed.first { _ in true } }) { checkReport(report) }

        guard let failing, let neverFinishing else {
            Issue.record("limits need the neverFinishing and failing wirings", sourceLocation: location)
            return
        }
        do {
            _ = try await failing.fetch()
            Issue.record("the failing wiring did not fail", sourceLocation: location)
        } catch {
            checkFailure(error)
        }

        let fetch = Task { try await neverFinishing.fetch() }
        try? await Task.sleep(for: .milliseconds(50))  // let the fetch get under way before cancelling it
        fetch.cancel()
        let finished = await withTimeout(.seconds(2)) { () -> Bool? in
            _ = await fetch.result
            return true
        }
        #expect(finished == true, "fetch() ignored cancellation", sourceLocation: location)
    }

    private static func checkActivity(
        _ activity: any ActivitySource, of id: ProviderID, fileEvents: FakeFileEvents?, at location: SourceLocation
    ) async {
        guard let fileEvents else {
            Issue.record("activity needs the fileEvents fake", sourceLocation: location)
            return
        }
        let stream = activity.reports()
        let report = await withTimeout(.seconds(2)) { await stream.first { _ in true } }
        #expect(report?.provider == id, "no initial activity report of its own", sourceLocation: location)

        let consumer = Task { for await _ in stream {} }
        consumer.cancel()
        await consumer.value
        let released = await withTimeout(.seconds(2)) { () -> Bool? in
            while fileEvents.activeStreams > 0 { try? await Task.sleep(for: .milliseconds(10)) }
            return true
        }
        #expect(released == true, "watching survived cancellation", sourceLocation: location)
    }

    /// The operation's result, or `nil` if it takes longer than `limit`; a stuck operation is left behind.
    private static func withTimeout<T: Sendable>(
        _ limit: Duration, _ operation: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let resume: @Sendable (T?) -> Void = { value in
                let first = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(returning: value) }
            }
            Task { resume(await operation()) }
            Task {
                try? await Task.sleep(for: limit)
                resume(nil)
            }
        }
    }
}
