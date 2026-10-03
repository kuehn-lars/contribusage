import Foundation
import os

/// SPEC §13: API key billing is checked again every 6 h.
private let unsupportedPlanRecheck: Duration = .seconds(6 * 3600)
private let log = Logger(subsystem: "contribusage", category: "refresh")

/// Runs the polled limits sources of the enabled providers, then GitHub, on the schedule of SPEC §12, one fetch at a
/// time in registry order (NFR-18), and persists each success to `state.json` (FR-10). The app feeds it conditions and
/// shows its updates. `GitHubValue` is GitHub's report, which the core cannot import (NFR-17, ADR-022).
public actor RefreshCoordinator<GitHubValue: Sendable & Codable> {
    public typealias Update = @Sendable (ProviderID, SourceState<LimitsReport>) async -> Void

    /// One polled source: a provider's limits, or GitHub as the app supplies it. `triggers` are the extra refresh dates
    /// a fetched value brings (FR-11: a window's reset). `interval` is the interval setting, read before every
    /// scheduling decision; `nil` keeps the policy's default.
    public struct Job<Value: Sendable & Codable>: Sendable {
        let policy: SchedulePolicy
        let origin: Origin
        let fetch: @Sendable () async throws -> Value
        let onUpdate: @Sendable (SourceState<Value>) async -> Void
        let triggers: @Sendable (Value) -> [Date]
        let interval: @Sendable () -> Duration?

        public init(
            policy: SchedulePolicy, origin: Origin, fetch: @escaping @Sendable () async throws -> Value,
            onUpdate: @escaping @Sendable (SourceState<Value>) async -> Void,
            triggers: @escaping @Sendable (Value) -> [Date] = { _ in [] },
            interval: @escaping @Sendable () -> Duration? = { nil }
        ) {
            self.policy = policy
            self.origin = origin
            self.fetch = fetch
            self.onUpdate = onUpdate
            self.triggers = triggers
            self.interval = interval
        }
    }

    /// FR-13 to FR-15: the settings, read before every plan, and the app's delivery.
    public struct Notifications: Sendable {
        let settings: @Sendable () -> NotificationPlanner.Settings
        let deliver: @Sendable ([NotificationPlanner.Note]) async -> Void

        public init(
            settings: @escaping @Sendable () -> NotificationPlanner.Settings,
            deliver: @escaping @Sendable ([NotificationPlanner.Note]) async -> Void
        ) {
            self.settings = settings
            self.deliver = deliver
        }
    }

    /// A job's schedule state. A class, so one `run` can update it across its `await`s; it never leaves the actor.
    private final class Record<Value: Sendable & Codable> {
        var snapshot: Snapshot<Value>?
        var lastAttempt: Date?
        var failures = 0
        var manual = false
        var state: SourceState<Value>?

        /// No token, or the service refused it: only a token change or a manual refresh runs the source again (SPEC §12,
        /// §8.4.3).
        var waitsForUser: Bool {
            switch state {
            case .notConfigured(.githubTokenMissing)?, .failed(.unauthorized, _)?: true
            default: false
            }
        }

        /// Being offline does not replace a state that waits for the user or for a rate limit's reset.
        var outlastsOffline: Bool {
            switch state {
            case .failed(.rateLimited, _)?: true
            default: waitsForUser
            }
        }
    }

    /// `state.json` (SPEC §10.7). Version 2: structured insights; the notification keys are optional, so no version.
    private struct PersistedState: PersistedFile {
        static var schemaVersion: Int { 2 }
        var limits: [ProviderID: Snapshot<LimitsReport>]
        var github: Snapshot<GitHubValue>?
        var notificationKeys: NotificationPlanner.Sent?
    }

    private let registry: ProviderRegistry
    private let stateFile: URL
    private let time: any TimeSource
    private let onUpdate: Update
    private let gitHubJob: Job<GitHubValue>?
    private let notifications: Notifications?
    private let limitsInterval: @Sendable (ProviderID) -> Duration?
    private var notificationKeys: NotificationPlanner.Sent = [:]
    private var conditions = ScheduleConditions()
    private var records: [ProviderID: Record<LimitsReport>] = [:]
    private var github = Record<GitHubValue>()
    /// FR-46: whether anything uses GitHub's data.
    private var gitHubWanted = true
    private var pass: Task<Date?, Never>?
    private var loop: Task<Void, Never>?

    /// `limitsInterval` is a provider's interval setting (for Claude Code: `provider.claude-code.probeInterval`).
    public init(
        registry: ProviderRegistry, paths: AppPaths, time: any TimeSource, github: Job<GitHubValue>?,
        notifications: Notifications? = nil,
        limitsInterval: @escaping @Sendable (ProviderID) -> Duration? = { _ in nil },
        onUpdate: @escaping Update
    ) {
        self.registry = registry
        stateFile = paths.root.appending(path: "state.json")
        self.time = time
        gitHubJob = github
        self.notifications = notifications
        self.limitsInterval = limitsInterval
        self.onUpdate = onUpdate
    }

    /// Shows the persisted snapshots, then keeps running what is due. Call again after enabling a provider.
    public func start() async {
        await restore()
        reschedule()
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        pass?.cancel()
    }

    /// FR-10: every enabled provider's and GitHub's last success shows at once, as `cache`; a snapshot already in
    /// memory stays, and a source that already shows a state keeps it. An unreadable file is a lost cache.
    public func restore() async {
        guard
            let persisted = (try? JSONStore.read(PersistedState.self, from: stateFile, using: LiveFileReader())) ?? nil
        else { return }
        for (id, snapshot) in persisted.limits where records[id]?.snapshot == nil {
            record(id).snapshot = snapshot.cached
        }
        if github.snapshot == nil { github.snapshot = persisted.github?.cached }
        if notificationKeys.isEmpty { notificationKeys = persisted.notificationKeys ?? [:] }
        for provider in await registry.enabledProviders() {
            if let job = job(for: provider), let record = records[provider.descriptor.id], record.state == nil,
                let snapshot = record.snapshot
            {
                await publish(job, record, .loaded(snapshot))
            }
        }
        if let gitHubJob, github.state == nil, let snapshot = github.snapshot {
            await publish(gitHubJob, github, .loaded(snapshot))
        }
    }

    /// Wake, sleep, network and Low Power Mode changes (SPEC §12 rules 1 to 3).
    public func update(_ conditions: ScheduleConditions) {
        self.conditions = conditions
        if loop != nil { reschedule() }
    }

    /// Manual refresh (SPEC §12 rule 4): a source within its `manualFloor` runs once the floor has passed.
    public func refreshNow() async {
        for provider in await registry.enabledProviders() where provider.descriptor.limitsPolicy != nil {
            record(provider.descriptor.id).manual = true
        }
        github.manual = true
        await runDue()
        if loop != nil { reschedule() }
    }

    /// An interval setting changed: the next run moves at once instead of after the old interval.
    public func intervalsChanged() {
        if loop != nil { reschedule() }
    }

    /// SPEC §11.6 "reset caches": every snapshot is forgotten and every source runs again. The notification keys stay,
    /// or the refetch would repeat notifications (FR-15); history is the providers' and never touched.
    public func resetCaches() async {
        records = [:]
        github = Record()
        persist()
        await runDue()
        if loop != nil { reschedule() }
    }

    /// SPEC §12 "token changed": GitHub starts over, and the old account's data leaves `state.json`. A fetch still
    /// running with the old token finishes into the replaced record, which nothing reads.
    public func gitHubTokenChanged() async {
        github = Record()
        persist()
        await runDue()
        if loop != nil { reschedule() }
    }

    /// FR-46: GitHub runs only while its block, its heatmap layer or the menu bar uses it (`Demand.github`). Wanted
    /// again, it runs what is due at once.
    public func setGitHubWanted(_ wanted: Bool) async {
        guard wanted != gitHubWanted else { return }
        gitHubWanted = wanted
        if wanted { await runDue() }
        if loop != nil { reschedule() }
    }

    /// SPEC §12 extra trigger: the popover opened, so data older than its source's minimum interval is refreshed now.
    /// Only this pass sees the trigger, so data younger than the minimum interval is left alone rather than refreshed later.
    public func popoverOpened() async {
        await runDue(openedAt: time.now)
        if loop != nil { reschedule() }
    }

    /// Runs every due source after any pass still running; returns when the next one is due, `nil` if none is scheduled.
    @discardableResult
    public func runDue() async -> Date? { await runDue(openedAt: nil) }

    @discardableResult
    private func runDue(openedAt: Date?) async -> Date? {
        let previous = pass
        let next = Task {
            _ = await previous?.value
            return await runPass(openedAt: openedAt)
        }
        pass = next
        return await next.value
    }

    private func reschedule() {
        loop?.cancel()
        loop = Task {
            while !Task.isCancelled, let next = await runDue() {
                // SPEC §16.5 "Low Power Mode: intervals doubled (check log)".
                log.info(
                    "next pass \(next.description, privacy: .public), Low Power Mode \(self.conditions.isLowPowerMode, privacy: .public)"
                )
                let wait = max(next.timeIntervalSince(time.now), 0)
                try? await Task.sleep(for: .seconds(wait), tolerance: .seconds(wait / 10))  // NFR-14
            }
        }
    }

    private func runPass(openedAt: Date?) async -> Date? {
        var next: [Date?] = []
        for provider in await registry.enabledProviders() {
            guard let job = job(for: provider) else { continue }
            next.append(await run(job, record(provider.descriptor.id), openedAt: openedAt))
        }
        if let gitHubJob, gitHubWanted { next.append(await run(gitHubJob, github, openedAt: openedAt)) }
        return next.compactMap(\.self).min()
    }

    /// Marks a job offline or runs it when due; returns when it is due next.
    private func run<Value>(_ job: Job<Value>, _ record: Record<Value>, openedAt: Date?) async -> Date? {
        if job.policy.needsNetwork && !conditions.isOnline {
            if !record.outlastsOffline { await publish(job, record, .failed(.offline, previous: record.snapshot)) }
            return nil
        }
        if let due = nextRun(job, record, openedAt: openedAt), due <= time.now { await refresh(job, record) }
        return nextRun(job, record, openedAt: nil)
    }

    private func nextRun<Value>(_ job: Job<Value>, _ record: Record<Value>, openedAt: Date?) -> Date? {
        var policy = job.policy.withDefault(job.interval())
        var manual = record.manual
        switch record.state {
        case .notConfigured(.unsupportedPlan)?:
            policy = policy.fixed(unsupportedPlanRecheck, manualFloor: policy.manualFloor)
        case .failed(.rateLimited(let until), _)?:
            // SPEC §13 "retrying at 15:04": `Schedule` adds the wait to the last attempt, so the run lands exactly on
            // `until`; a manual refresh or the popover cannot bring it forward.
            let wait = Duration.seconds(max(until.timeIntervalSince(record.lastAttempt ?? time.now), 0))
            policy = policy.fixed(wait, manualFloor: wait)
        case .failed(.offline, _)?:
            manual = true  // SPEC §12 rule 2: it runs on reconnect, within its floor.
        default:
            if record.waitsForUser && !record.manual { return nil }
        }
        // `Schedule` counts only triggers after the last run.
        let triggers = (record.snapshot.map { job.triggers($0.value) } ?? []) + [openedAt].compactMap(\.self)
        return Schedule.nextRun(
            policy: policy, lastSuccess: record.snapshot?.fetchedAt, lastAttempt: record.lastAttempt,
            failures: record.failures, now: time.now, conditions: conditions, manual: manual,
            triggers: triggers)
    }

    private func refresh<Value>(_ job: Job<Value>, _ record: Record<Value>) async {
        let previous = record.snapshot
        record.lastAttempt = time.now
        record.manual = false
        await publish(job, record, .loading(previous: previous))
        let state: SourceState<Value>
        do {
            let snapshot = Snapshot(value: try await job.fetch(), fetchedAt: time.now, origin: job.origin)
            record.snapshot = snapshot
            persist()
            state = .loaded(snapshot)
        } catch is CancellationError {
            return
        } catch {
            state = Self.state(after: error, previous: previous)
        }
        switch state {
        case .loaded, .notConfigured(.unsupportedPlan): record.failures = 0
        default: record.failures += 1
        }
        await publish(job, record, state)
    }

    /// SPEC §13.
    private static func state<Value>(after error: any Error, previous: Snapshot<Value>?) -> SourceState<Value> {
        switch error as? SourceError ?? .providerSpecific(code: "unexpected", message: "\(error)") {
        case .unsupportedPlan(let note): .notConfigured(.unsupportedPlan(note: note))
        case .toolNotFound: .notConfigured(.toolNotInstalled)
        case .tokenMissing: .notConfigured(.githubTokenMissing)
        case let error: .failed(error, previous: previous)
        }
    }

    private func publish<Value>(_ job: Job<Value>, _ record: Record<Value>, _ state: SourceState<Value>) async {
        record.state = state
        await job.onUpdate(state)
    }

    /// A provider's limits as a job: snapshots from `fetch()` carry `.poll`, a window's reset triggers a refresh.
    private func job(for provider: any UsageProvider) -> Job<LimitsReport>? {
        guard let source = provider.limits, let policy = provider.descriptor.limitsPolicy else { return nil }
        let id = provider.descriptor.id
        let descriptor = provider.descriptor
        return Job(
            policy: policy, origin: .poll,
            fetch: {
                let report = try await source.fetch()
                await self.notify(report, descriptor)
                return report
            },
            onUpdate: { [onUpdate] in await onUpdate(id, $0) }, triggers: { $0.windows.compactMap(\.resetsAt) },
            interval: { [limitsInterval] in limitsInterval(id) })
    }

    /// FR-15: the keys are persisted before delivery, so a restart cannot repeat a notification. Runs only on a fetch,
    /// never on a restored snapshot.
    private func notify(_ report: LimitsReport, _ descriptor: ProviderDescriptor) async {
        guard let notifications else { return }
        let before = notificationKeys
        let notes = NotificationPlanner.plan(
            report, displayName: descriptor.displayName, windowTitle: descriptor.toolText,
            settings: notifications.settings(), sent: &notificationKeys, now: time.now)
        if notificationKeys != before { persist() }
        if !notes.isEmpty { await notifications.deliver(notes) }
    }

    private func record(_ id: ProviderID) -> Record<LimitsReport> {
        if let record = records[id] { return record }
        let record = Record<LimitsReport>()
        records[id] = record
        return record
    }

    /// SPEC §13: a failed write keeps the state in memory and is retried with the next success.
    private func persist() {
        do {
            try JSONStore.write(
                PersistedState(
                    limits: records.compactMapValues(\.snapshot), github: github.snapshot,
                    notificationKeys: notificationKeys),
                to: stateFile)
        } catch {
            log.error("state.json not written: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension SchedulePolicy {
    /// This policy with `interval` as its default; `Schedule` clamps it to the bounds.
    fileprivate func withDefault(_ interval: Duration?) -> SchedulePolicy {
        guard let interval else { return self }
        return SchedulePolicy(
            defaultInterval: interval, minimumInterval: minimumInterval, maximumInterval: maximumInterval,
            staleAfter: staleAfter, manualFloor: manualFloor, needsNetwork: needsNetwork)
    }

    /// This policy with every interval `interval`, so backoff and triggers cannot move a run.
    fileprivate func fixed(_ interval: Duration, manualFloor: Duration) -> SchedulePolicy {
        SchedulePolicy(
            defaultInterval: interval, minimumInterval: interval, maximumInterval: interval, staleAfter: staleAfter,
            manualFloor: manualFloor, needsNetwork: needsNetwork)
    }
}

extension Snapshot {
    /// FR-10: a persisted snapshot as the UI shows it after launch.
    fileprivate var cached: Snapshot { Snapshot(value: value, fetchedAt: fetchedAt, origin: .cache) }
}
