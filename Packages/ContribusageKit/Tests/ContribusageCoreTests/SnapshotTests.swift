import ContribusageCore
import Foundation
import Testing

private let fetched = Snapshot(value: 1, fetchedAt: Date(timeIntervalSince1970: 0), origin: .cache)

/// SPEC §11.3: every state but "not configured" and "first load" can show values.
@Test func sourceStateExposesTheSnapshotItCanShow() {
    #expect(SourceState<Int>.notConfigured(.noLocalData).snapshot == nil)
    #expect(SourceState<Int>.loading(previous: nil).snapshot == nil)
    #expect(SourceState.loading(previous: fetched).snapshot == fetched)
    #expect(SourceState.loaded(fetched).snapshot == fetched)
    #expect(SourceState.failed(.offline, previous: fetched).snapshot == fetched)
    #expect(SourceState<Int>.failed(.offline, previous: nil).snapshot == nil)
}

/// SPEC §12 "stale after".
@Test func snapshotIsStaleOnlyPastTheLimit() {
    #expect(!fetched.isStale(at: Date(timeIntervalSince1970: 1800), after: .seconds(1800)))
    #expect(fetched.isStale(at: Date(timeIntervalSince1970: 1801), after: .seconds(1800)))
}

/// FR-36: one diagnostics line per source, the error in full.
@Test func sourceStateDescribesItselfForDiagnostics() {
    #expect(SourceState<Int>.notConfigured(.noLocalData).diagnostics == "not configured: noLocalData")
    #expect(SourceState<Int>.loading(previous: nil).diagnostics == "loading")
    #expect(SourceState.loaded(fetched).diagnostics == "loaded, fetched 1970-01-01T00:00:00Z")
    #expect(
        SourceState.failed(.processFailed(exitCode: 2, stderrTail: "boom"), previous: fetched).diagnostics
            == #"failed: processFailed(exitCode: 2, stderrTail: "boom"), fetched 1970-01-01T00:00:00Z"#)
}
