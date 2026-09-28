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
