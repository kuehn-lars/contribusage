import ContribusageCore
import ContribusageTestSupport
import Foundation
import Testing
import os

/// SPEC §12, §16.3, FR-10, NFR-18: the coordinator runs polled limits sources through `Schedule`.

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let a = ProviderID(rawValue: "a")
private let b = ProviderID(rawValue: "b")

/// A polled limits source with the probe row of SPEC §12; `fetch` runs for every refresh.
private struct PolledProvider: UsageProvider, LimitsSource {
    let id: ProviderID
    let fetch: @Sendable (ProviderID) async throws -> LimitsReport

    var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: id, displayName: "Polled", symbolName: "gauge", capabilities: .limits, tokenCategories: [],
            limitsPolicy: SchedulePolicy(
                defaultInterval: .seconds(900), minimumInterval: .seconds(300), maximumInterval: .seconds(3600),
                staleAfter: .seconds(1800), manualFloor: .seconds(30), needsNetwork: true))
    }
    var limits: (any LimitsSource)? { self }
    var activity: (any ActivitySource)? { nil }
    func detectAvailability() async -> ProviderAvailability { .available(version: "1") }
    func fetch() async throws -> LimitsReport { try await fetch(id) }
    func pushedUpdates() -> AsyncStream<LimitsReport> { AsyncStream { $0.finish() } }
}

private func report(_ id: ProviderID, resetsAt: Date? = nil) -> LimitsReport {
    LimitsReport(
        provider: id,
        windows: [UsageWindow(label: "Week", kind: .weekly, usedPercent: 5, isBelowOne: false, resetsAt: resetsAt)],
        billingNote: nil, insights: nil, rawOutput: nil)
}

/// Records fetches and state updates.
private final class Log: Sendable {
    private let state = OSAllocatedUnfairLock(
        initialState: (
            fetches: [ProviderID](), running: 0, maxRunning: 0, updates: [(ProviderID, SourceState<LimitsReport>)]()
        ))

    var fetches: [ProviderID] { state.withLock { $0.fetches } }
    var maxRunning: Int { state.withLock { $0.maxRunning } }
    var updates: [(ProviderID, SourceState<LimitsReport>)] { state.withLock { $0.updates } }

    func fetch(_ id: ProviderID, pause: Duration = .zero, resetsAt: Date? = nil) async throws -> LimitsReport {
        state.withLock {
            $0.fetches.append(id)
            $0.running += 1
            $0.maxRunning = max($0.maxRunning, $0.running)
        }
        try? await Task.sleep(for: pause)
        state.withLock { $0.running -= 1 }
        return report(id, resetsAt: resetsAt)
    }

    func record(_ id: ProviderID, _ update: SourceState<LimitsReport>) {
        state.withLock { $0.updates.append((id, update)) }
    }
}

private func coordinator(
    _ providers: [any UsageProvider], enabled: Set<ProviderID>? = nil, paths: AppPaths = temporaryPaths(),
    time: FakeTimeSource = FakeTimeSource(now: start), log: Log
) -> RefreshCoordinator {
    RefreshCoordinator(
        registry: ProviderRegistry(
            providers: providers, enabledIDs: enabled ?? Set(providers.map(\.descriptor.id)), time: time),
        paths: paths, time: time, onUpdate: { log.record($0, $1) })
}

private func temporaryPaths() -> AppPaths {
    AppPaths(root: FileManager.default.temporaryDirectory.appending(path: "contribusage-\(UUID())/root/"))
}

/// NFR-18, SPEC §12 rule 5: two overlapping passes still run one fetch at a time, in registry order.
@Test func dueSourcesRunOneAtATimeInRegistryOrder() async {
    let log = Log()
    let coordinator = coordinator(
        [b, a].map { id in PolledProvider(id: id) { try await log.fetch($0, pause: .milliseconds(50)) } }, log: log)

    async let first = coordinator.runDue()
    async let second = coordinator.runDue()
    _ = await (first, second)

    #expect(log.fetches == [b, a])
    #expect(log.maxRunning == 1)
}

/// SPEC §12 rule 6, also for manual refresh; a push-only source (no policy) is never polled either.
@Test func disabledAndPushOnlySourcesAreNeverScheduled() async {
    let log = Log()
    let pushOnly = FakeProvider(fetch: { try await log.fetch(.fake) })
    let coordinator = coordinator(
        [
            PolledProvider(id: a) { try await log.fetch($0) }, PolledProvider(id: b) { try await log.fetch($0) },
            pushOnly,
        ],
        enabled: [a, .fake], log: log)

    _ = await coordinator.runDue()
    await coordinator.refreshNow()

    #expect(log.fetches == [a])
}

/// FR-10: the last success survives a restart, shows at once as `cache` and keeps its schedule.
@Test func aSuccessIsPersistedAndShownOnLaunch() async {
    let paths = temporaryPaths()
    let time = FakeTimeSource(now: start)
    let log = Log()
    let first = coordinator([PolledProvider(id: a) { try await log.fetch($0) }], paths: paths, time: time, log: log)
    _ = await first.runDue()
    await first.restore()  // `start()` again, after enabling a provider
    guard case (a, .loaded(let fresh))? = log.updates.last else {
        Issue.record("no snapshot: \(log.updates)")
        return
    }
    #expect(fresh.origin == .poll)

    time.advance(by: .seconds(60))
    let relaunchLog = Log()
    let relaunched = coordinator(
        [PolledProvider(id: a) { try await relaunchLog.fetch($0) }], paths: paths, time: time, log: relaunchLog)
    await relaunched.restore()
    let next = await relaunched.runDue()

    guard case (a, .loaded(let snapshot))? = relaunchLog.updates.first else {
        Issue.record("no restored snapshot: \(relaunchLog.updates)")
        return
    }
    #expect(snapshot.origin == .cache)
    #expect(snapshot.fetchedAt == start)
    #expect(snapshot.value == report(a))
    #expect(relaunchLog.fetches.isEmpty)
    #expect(next == start + 900)
}

/// SPEC §13: a failure keeps the previous snapshot and backs off.
@Test func aFailureKeepsThePreviousSnapshotAndBacksOff() async {
    let time = FakeTimeSource(now: start)
    let fail = OSAllocatedUnfairLock(initialState: false)
    let log = Log()
    let coordinator = coordinator(
        [
            PolledProvider(id: a) {
                if fail.withLock({ $0 }) { throw SourceError.timedOut }
                return try await log.fetch($0)
            }
        ], time: time, log: log)
    _ = await coordinator.runDue()

    fail.withLock { $0 = true }
    time.advance(by: .seconds(900))
    let next = await coordinator.runDue()

    guard case (a, .failed(.timedOut, let previous?))? = log.updates.last else {
        Issue.record("no failure: \(log.updates)")
        return
    }
    #expect(previous.fetchedAt == start)
    #expect(next == time.now + 1800)
}

/// SPEC §13: API key billing is `notConfigured` and checked again after 6 h, not on the backoff schedule.
@Test func unsupportedPlanIsNotConfiguredAndRecheckedAfterSixHours() async {
    let log = Log()
    let coordinator = coordinator(
        [PolledProvider(id: a) { _ in throw SourceError.unsupportedPlan(note: "API Usage Billing") }], log: log)

    let next = await coordinator.runDue()

    guard case (a, .notConfigured(.unsupportedPlan(note: "API Usage Billing")))? = log.updates.last else {
        Issue.record("not unsupported: \(log.updates)")
        return
    }
    #expect(next == start + 6 * 3600)
}

/// SPEC §12 rule 2: offline marks a network source without running it; reconnecting runs it.
@Test func offlineMarksTheSourceAndReconnectingRunsIt() async {
    let log = Log()
    let coordinator = coordinator([PolledProvider(id: a) { try await log.fetch($0) }], log: log)

    await coordinator.update(ScheduleConditions(isOnline: false))
    #expect(await coordinator.runDue() == nil)
    guard case (a, .failed(.offline, nil))? = log.updates.last else {
        Issue.record("not offline: \(log.updates)")
        return
    }
    #expect(log.fetches.isEmpty)

    await coordinator.update(ScheduleConditions())
    _ = await coordinator.runDue()
    #expect(log.fetches == [a])
}

/// SPEC §12 rule 4.
@Test func manualRefreshRunsEarlyButNotWithinTheFloor() async {
    let time = FakeTimeSource(now: start)
    let log = Log()
    let coordinator = coordinator([PolledProvider(id: a) { try await log.fetch($0) }], time: time, log: log)
    _ = await coordinator.runDue()

    time.advance(by: .seconds(10))
    await coordinator.refreshNow()
    #expect(log.fetches == [a])

    time.advance(by: .seconds(20))
    _ = await coordinator.runDue()
    #expect(log.fetches == [a, a])
}

/// SPEC §13: a missing tool is `notConfigured`, an untyped error `providerSpecific`; both back off.
@Test func missingToolAndUntypedErrorsMapAndBackOff() async {
    let log = Log()
    let coordinator = coordinator(
        [
            PolledProvider(id: a) { _ in throw SourceError.toolNotFound },
            PolledProvider(id: b) { _ in throw URLError(.cannotFindHost) },
        ], log: log)

    let next = await coordinator.runDue()

    guard case (a, .notConfigured(.toolNotInstalled))? = log.updates.first(where: { $0.0 == a && !isLoading($0.1) }),
        case (b, .failed(.providerSpecific(code: "unexpected", _), nil))? = log.updates.last
    else {
        Issue.record("unexpected states: \(log.updates)")
        return
    }
    #expect(next == start + 1800)
}

/// SPEC §12 "popover opened and data older than 5 min": younger data is left alone, and the trigger does not linger.
@Test func openingThePopoverRefreshesDataOlderThanTheMinimumInterval() async {
    let time = FakeTimeSource(now: start)
    let log = Log()
    let coordinator = coordinator([PolledProvider(id: a) { try await log.fetch($0) }], time: time, log: log)
    _ = await coordinator.runDue()

    time.advance(by: .seconds(240))
    await coordinator.popoverOpened()
    time.advance(by: .seconds(120))
    _ = await coordinator.runDue()
    #expect(log.fetches == [a])

    await coordinator.popoverOpened()
    #expect(log.fetches == [a, a])
}

/// FR-11: a window's reset brings the next refresh forward once, but not within the minimum interval.
@Test func aWindowsResetSchedulesOneRefresh() async {
    let time = FakeTimeSource(now: start)
    let log = Log()
    let coordinator = coordinator(
        [
            PolledProvider(id: a) { try await log.fetch($0, resetsAt: start + 600) },
            PolledProvider(id: b) { try await log.fetch($0, resetsAt: start + 60) },
        ], time: time, log: log)

    #expect(await coordinator.runDue() == start + 300)
    time.advance(by: .seconds(300))
    #expect(await coordinator.runDue() == start + 600)
    time.advance(by: .seconds(300))
    #expect(await coordinator.runDue() == start + 300 + 900)
    #expect(log.fetches == [a, b, b, a])
}

private func isLoading(_ state: SourceState<LimitsReport>) -> Bool {
    if case .loading = state { true } else { false }
}
