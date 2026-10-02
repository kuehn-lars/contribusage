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

private func report(_ id: ProviderID, percent: Double = 5, resetsAt: Date? = nil) -> LimitsReport {
    LimitsReport(
        provider: id,
        windows: [
            UsageWindow(label: "Week", kind: .weekly, usedPercent: percent, isBelowOne: false, resetsAt: resetsAt)
        ],
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
    _ providers: [any UsageProvider], enabled: Set<ProviderID>? = nil, paths: AppPaths = .temporary(),
    time: FakeTimeSource = FakeTimeSource(now: start), log: Log, github: RefreshCoordinator<Int>.Job<Int>? = nil,
    notifications: RefreshCoordinator<Int>.Notifications? = nil
) -> RefreshCoordinator<Int> {
    RefreshCoordinator(
        registry: ProviderRegistry(
            providers: providers, enabledIDs: enabled ?? Set(providers.map(\.descriptor.id)), time: time),
        paths: paths, time: time, github: github, notifications: notifications, onUpdate: { log.record($0, $1) })
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
    let paths = AppPaths.temporary()
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

/// FR-15, US-3: a fetched report is planned and delivered; the sent keys survive a restart, a cached report sends nothing.
@Test func notificationsAreSentOnceAcrossARestart() async {
    let paths = AppPaths.temporary()
    let time = FakeTimeSource(now: start)
    let sent = OSAllocatedUnfairLock(initialState: [String]())
    let notifications = RefreshCoordinator<Int>.Notifications(
        settings: { NotificationPlanner.Settings(thresholds: [50]) },
        deliver: { notes in sent.withLock { $0 += notes.map(\.title) } })
    let provider = PolledProvider(id: a) { report($0, percent: 60) }
    _ = await coordinator([provider], paths: paths, time: time, log: Log(), notifications: notifications).runDue()
    #expect(sent.withLock { $0 } == ["Polled: Week at 50 %"])

    time.advance(by: .seconds(3600))
    let relaunched = coordinator([provider], paths: paths, time: time, log: Log(), notifications: notifications)
    await relaunched.restore()
    _ = await relaunched.runDue()
    #expect(sent.withLock { $0 }.count == 1)
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

/// SPEC §12 GitHub row, with a value the core cannot name standing in for `GitHubReport`.
private let gitHubPolicy = SchedulePolicy(
    defaultInterval: .seconds(1800), minimumInterval: .seconds(600), maximumInterval: .seconds(6 * 3600),
    staleAfter: .seconds(7200), manualFloor: .seconds(30), needsNetwork: true)

/// Answers GitHub fetches with `answer` and records the states.
private final class GitHubLog: Sendable {
    private let state = OSAllocatedUnfairLock(
        initialState: (answer: Result<Int, SourceError>.success(1), fetches: 0, updates: [SourceState<Int>]()))

    var fetches: Int { state.withLock { $0.fetches } }
    var last: SourceState<Int>? { state.withLock { $0.updates.last } }
    func answer(_ answer: Result<Int, SourceError>) { state.withLock { $0.answer = answer } }

    var job: RefreshCoordinator<Int>.Job<Int> {
        RefreshCoordinator.Job(
            policy: gitHubPolicy, origin: .github,
            fetch: {
                try self.state.withLock {
                    $0.fetches += 1
                    return $0.answer
                }.get()
            },
            onUpdate: { update in self.state.withLock { $0.updates.append(update) } })
    }
}

/// ADR-018: GitHub runs in the same passes, persists next to the limits and shows on launch as `cache`.
@Test func gitHubRunsInThePassesAndIsRestored() async {
    let paths = AppPaths.temporary()
    let time = FakeTimeSource(now: start)
    let github = GitHubLog()
    let first = coordinator(
        [PolledProvider(id: a) { try await Log().fetch($0) }], paths: paths, time: time, log: Log(), github: github.job)
    #expect(await first.runDue() == start + 900)
    guard case .loaded(let fresh)? = github.last else {
        Issue.record("not loaded: \(String(describing: github.last))")
        return
    }
    #expect(fresh.origin == .github)
    #expect(fresh.value == 1)

    let relaunched = GitHubLog()
    let log = Log()
    let second = coordinator(
        [PolledProvider(id: a) { try await log.fetch($0) }], paths: paths, time: time, log: log,
        github: relaunched.job)
    await second.restore()
    guard case .loaded(let cached)? = relaunched.last, case (a, .loaded)? = log.updates.last else {
        Issue.record("not restored: \(String(describing: relaunched.last)), \(log.updates)")
        return
    }
    #expect(cached.origin == .cache)
    #expect(cached.fetchedAt == start)
    #expect(await second.runDue() == start + 900)
    #expect(relaunched.fetches == 0)
}

/// SPEC §12, §8.4.3: no token and 401 stop automatic runs, offline included; Retry and a token change run it again.
@Test(arguments: [Result<Int, SourceError>.failure(.tokenMissing), .failure(.unauthorized)])
func aMissingOrRejectedTokenWaitsForTheUser(answer: Result<Int, SourceError>) async {
    let paths = AppPaths.temporary()
    let time = FakeTimeSource(now: start)
    let github = GitHubLog()
    github.answer(answer)
    let coordinator = coordinator([], paths: paths, time: time, log: Log(), github: github.job)
    #expect(await coordinator.runDue() == nil)
    #expect(isWaiting(github.last))

    await coordinator.update(ScheduleConditions(isOnline: false))
    time.advance(by: .seconds(7 * 3600))
    #expect(await coordinator.runDue() == nil)
    await coordinator.update(ScheduleConditions())
    #expect(await coordinator.runDue() == nil)
    #expect(github.fetches == 1)
    #expect(isWaiting(github.last))

    await coordinator.refreshNow()
    #expect(github.fetches == 2)

    github.answer(.success(2))
    await coordinator.gitHubTokenChanged()
    #expect(github.fetches == 3)
    guard case .loaded(let snapshot)? = github.last else {
        Issue.record("not loaded: \(String(describing: github.last))")
        return
    }
    #expect(snapshot.value == 2)
}

/// A removed token drops the old account's data from memory and from `state.json`.
@Test func removingTheTokenForgetsTheSnapshot() async {
    let paths = AppPaths.temporary()
    let github = GitHubLog()
    let first = coordinator([], paths: paths, log: Log(), github: github.job)
    _ = await first.runDue()

    github.answer(.failure(.tokenMissing))
    await first.gitHubTokenChanged()
    guard case .notConfigured(.githubTokenMissing)? = github.last else {
        Issue.record("still configured: \(String(describing: github.last))")
        return
    }

    let relaunched = GitHubLog()
    await coordinator([], paths: paths, log: Log(), github: relaunched.job).restore()
    #expect(relaunched.last == nil)
}

/// SPEC §12, §13 "retrying at 15:04": a rate limit runs again at its reset, neither earlier nor later.
@Test func aRateLimitWaitsForItsReset() async {
    let time = FakeTimeSource(now: start)
    let github = GitHubLog()
    github.answer(.failure(.rateLimited(until: start + 120)))
    let coordinator = coordinator([], time: time, log: Log(), github: github.job)
    #expect(await coordinator.runDue() == start + 120)

    time.advance(by: .seconds(60))
    await coordinator.refreshNow()
    await coordinator.popoverOpened()
    #expect(github.fetches == 1)

    github.answer(.success(1))
    time.advance(by: .seconds(60))
    #expect(await coordinator.runDue() == start + 120 + 1800)
    #expect(github.fetches == 2)
}

private func isWaiting(_ state: SourceState<Int>?) -> Bool {
    switch state {
    case .notConfigured(.githubTokenMissing)?, .failed(.unauthorized, nil)?: true
    default: false
    }
}

private func isLoading(_ state: SourceState<LimitsReport>) -> Bool {
    if case .loading = state { true } else { false }
}
