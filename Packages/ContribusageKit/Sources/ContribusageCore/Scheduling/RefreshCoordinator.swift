import Foundation
import os

/// Runs the polled limits sources of the enabled providers on the schedule of SPEC §12, one fetch at a time in registry
/// order (NFR-18), and persists each success to `state.json` (FR-10). The app feeds it conditions and shows its updates.
public actor RefreshCoordinator {
    public typealias Update = @Sendable (ProviderID, SourceState<LimitsReport>) async -> Void

    private struct Record {
        var snapshot: Snapshot<LimitsReport>?
        var lastAttempt: Date?
        var failures = 0
        var manual = false
        var state: SourceState<LimitsReport>?
    }

    /// `state.json` (SPEC §10.7); GitHub snapshots and notification keys join as optional fields.
    private struct PersistedState: PersistedFile {
        static let schemaVersion = 1
        var limits: [ProviderID: Snapshot<LimitsReport>]
    }

    /// SPEC §13: API key billing is checked again every 6 h.
    private static let unsupportedPlanRecheck: Duration = .seconds(6 * 3600)
    private static let log = Logger(subsystem: "contribusage", category: "refresh")

    private let registry: ProviderRegistry
    private let stateFile: URL
    private let time: any TimeSource
    private let onUpdate: Update
    private var conditions = ScheduleConditions()
    private var records: [ProviderID: Record] = [:]
    private var pass: Task<Date?, Never>?
    private var loop: Task<Void, Never>?

    public init(registry: ProviderRegistry, paths: AppPaths, time: any TimeSource, onUpdate: @escaping Update) {
        self.registry = registry
        stateFile = paths.root.appending(path: "state.json")
        self.time = time
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

    /// FR-10: every enabled provider's last success shows at once, as `cache`; a snapshot already in memory stays.
    /// An unreadable file is a lost cache.
    public func restore() async {
        guard let persisted = (try? JSONStore.read(PersistedState.self, from: stateFile)) ?? nil else { return }
        for (id, snapshot) in persisted.limits where records[id]?.snapshot == nil {
            records[id, default: Record()].snapshot = Snapshot(
                value: snapshot.value, fetchedAt: snapshot.fetchedAt, origin: .cache)
        }
        for provider in await registry.enabledProviders() {
            let id = provider.descriptor.id
            if let snapshot = records[id]?.snapshot { await publish(id, .loaded(snapshot)) }
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
            records[provider.descriptor.id, default: Record()].manual = true
        }
        await runDue()
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
                let wait = max(next.timeIntervalSince(time.now), 0)
                try? await Task.sleep(for: .seconds(wait), tolerance: .seconds(wait / 10))  // NFR-14
            }
        }
    }

    private func runPass(openedAt: Date?) async -> Date? {
        var earliest: Date?
        for provider in await registry.enabledProviders() {
            guard let source = provider.limits, let policy = provider.descriptor.limitsPolicy else { continue }
            let id = provider.descriptor.id
            if policy.needsNetwork && !conditions.isOnline {
                await publish(id, .failed(.offline, previous: records[id]?.snapshot))
                continue
            }
            if let due = nextRun(id, policy, openedAt: openedAt), due <= time.now { await refresh(id, source) }
            if let next = nextRun(id, policy) { earliest = min(earliest ?? next, next) }
        }
        return earliest
    }

    private func nextRun(_ id: ProviderID, _ policy: SchedulePolicy, openedAt: Date? = nil) -> Date? {
        let record = records[id, default: Record()]
        var policy = policy
        if case .notConfigured(.unsupportedPlan)? = record.state {
            let recheck = Self.unsupportedPlanRecheck
            policy = SchedulePolicy(
                defaultInterval: recheck, minimumInterval: recheck, maximumInterval: recheck,
                staleAfter: policy.staleAfter, manualFloor: policy.manualFloor, needsNetwork: policy.needsNetwork)
        }
        // FR-11: a window's reset triggers a refresh; `Schedule` counts only triggers after the last run.
        let resets = record.snapshot?.value.windows.compactMap(\.resetsAt) ?? []
        return Schedule.nextRun(
            policy: policy, lastSuccess: record.snapshot?.fetchedAt, lastAttempt: record.lastAttempt,
            failures: record.failures, now: time.now, conditions: conditions, manual: record.manual,
            triggers: resets + [openedAt].compactMap(\.self))
    }

    private func refresh(_ id: ProviderID, _ source: any LimitsSource) async {
        let previous = records[id]?.snapshot
        records[id, default: Record()].lastAttempt = time.now
        records[id]!.manual = false
        await publish(id, .loading(previous: previous))
        let state: SourceState<LimitsReport>
        do {
            let snapshot = Snapshot(value: try await source.fetch(), fetchedAt: time.now, origin: .poll)
            records[id]!.snapshot = snapshot
            persist()
            state = .loaded(snapshot)
        } catch is CancellationError {
            return
        } catch {
            state = Self.state(after: error, previous: previous)
        }
        switch state {
        case .loaded, .notConfigured(.unsupportedPlan): records[id]!.failures = 0
        default: records[id]!.failures += 1
        }
        await publish(id, state)
    }

    /// SPEC §13.
    private static func state(after error: any Error, previous: Snapshot<LimitsReport>?) -> SourceState<LimitsReport> {
        switch error as? SourceError ?? .providerSpecific(code: "unexpected", message: "\(error)") {
        case .unsupportedPlan(let note): .notConfigured(.unsupportedPlan(note: note))
        case .toolNotFound: .notConfigured(.toolNotInstalled)
        case let error: .failed(error, previous: previous)
        }
    }

    private func publish(_ id: ProviderID, _ state: SourceState<LimitsReport>) async {
        records[id, default: Record()].state = state
        await onUpdate(id, state)
    }

    /// SPEC §13: a failed write keeps the state in memory and is retried with the next success.
    private func persist() {
        do {
            try JSONStore.write(PersistedState(limits: records.compactMapValues(\.snapshot)), to: stateFile)
        } catch {
            Self.log.error("state.json not written: \(error.localizedDescription, privacy: .public)")
        }
    }
}
