import ContribusageCore
import ContribusageGitHub
import Foundation
import Observation

/// The view model (SPEC §9.2): one `SourceState` per provider capability and one for GitHub.
@Observable final class AppState {
    /// One popover group (FR-4), in registry order. Disabled groups keep their last states, so turning a provider on
    /// again shows them at once.
    struct ProviderGroupState: Identifiable {
        let descriptor: ProviderDescriptor
        /// `nil` when the provider lacks the capability.
        var limits: SourceState<LimitsReport>?
        var activity: SourceState<ActivityReport>?
        var id: ProviderID { descriptor.id }
        /// FR-38: the insights the group can show; the `showInsights` setting decides whether it does.
        var insights: Insights? {
            descriptor.capabilities.contains(.insights) ? limits?.snapshot?.value.insights : nil
        }
    }

    var providers: [ProviderGroupState]
    /// FR-2: only these groups show in the popover.
    private(set) var enabledIDs: Set<ProviderID>
    var github: SourceState<GitHubReport>
    /// FR-44, FR-45: saved as JSON under `popoverLayout`; a change shows at once and starts or stops the work it
    /// changes (FR-46, US-13).
    var layout: PopoverLayout = .stored {
        didSet {
            PopoverLayout.stored = layout
            applyDemand()
        }
    }
    /// `nil` in previews, which never open Settings.
    @ObservationIgnored private(set) var registry: ProviderRegistry?
    /// `nil` in previews.
    @ObservationIgnored private var coordinator: RefreshCoordinator<GitHubReport>?
    /// `nil` in previews, which never open Settings.
    @ObservationIgnored private var gitHubAccount: GitHubAccount?
    @ObservationIgnored private var conditions: SystemConditions?
    /// `Demand.github` to the coordinator, through one consumer so the values arrive in order.
    @ObservationIgnored private var gitHubWanted: AsyncStream<Bool>.Continuation?
    /// The watched activity sources (FR-46: `Demand.activity`) and the tasks that consume their reports, rescanned on
    /// popover open and wake (SPEC §12); cancelling a task stops the watching (ADR-016).
    @ObservationIgnored private var activities: [ProviderID: (source: any ActivitySource, watch: Task<Void, Never>)] =
        [:]
    @ObservationIgnored private let time: any TimeSource

    /// `enabledIDs` defaults to every group in `providers`.
    init(
        providers: [ProviderGroupState], enabledIDs: Set<ProviderID>? = nil, github: SourceState<GitHubReport>,
        time: any TimeSource = SystemTimeSource()
    ) {
        self.providers = providers
        self.enabledIDs = enabledIDs ?? Set(providers.map(\.id))
        self.github = github
        self.time = time
    }

    /// The popover's groups.
    var enabledProviders: [ProviderGroupState] { providers.filter { enabledIDs.contains($0.id) } }

    /// The running app: the registered providers and GitHub on the coordinator, fed by the Mac's conditions (SPEC §12).
    static func live() -> AppState {
        let time = SystemTimeSource()
        let defaults = UserDefaults.standard
        let enabledIDs = defaults.stringArray(forKey: "enabledProviders").map { Set($0.map(ProviderID.init)) }
        let registry = ProviderRegistry(
            providers: ProviderRegistration.all(time: time), enabledIDs: enabledIDs, time: time)
        // None shows until the registry has settled the FR-2 first-run default.
        let state = AppState(
            providers: registry.providers.map(ProviderGroupState.init), enabledIDs: [], github: .loading(previous: nil),
            time: time)
        state.registry = registry
        // FR-16: Keychain service `<bundle id>.github`. Both Info.plist keys come from the build settings.
        let gitHubAccount = GitHubAccount(
            secrets: KeychainSecretStore(service: Bundle.main.bundleIdentifier! + ".github"),
            client: GitHubClient(
                transport: URLSessionTransport(),
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String))
        state.gitHubAccount = gitHubAccount
        let github = RefreshCoordinator<GitHubReport>.Job(
            policy: GitHubReport.policy, origin: .github,
            // ponytail: the Mac's calendar defines GitHub's today until R-4 names the zone GitHub counts in (ADR-021).
            fetch: { try await gitHubAccount.report(now: time.now, calendar: .current) },
            onUpdate: { [weak state] update in await state?.apply(update) },
            interval: { minutes(UserDefaults.standard.object(forKey: "githubInterval")) })
        // Read before every plan.
        let notifications = RefreshCoordinator<GitHubReport>.Notifications(
            settings: { .stored }, deliver: NotificationDelivery.shared.deliver)
        let coordinator = RefreshCoordinator(
            registry: registry, paths: .live, time: time, github: github, notifications: notifications,
            limitsInterval: { minutes(UserDefaults.standard.object(forKey: "provider.\($0.rawValue).probeInterval")) },
            onUpdate: { [weak state] id, update in await state?.apply(update, to: id) })
        state.coordinator = coordinator
        // One consumer keeps the changes in order; a task per change would not.
        let (changes, changed) = AsyncStream.makeStream(of: ScheduleConditions.self)
        state.conditions = SystemConditions { changed.yield($0) }
        Task {
            var lastWake: Date?
            for await conditions in changes {
                await coordinator.update(conditions)
                if conditions.lastWake != lastWake {
                    lastWake = conditions.lastWake
                    state.rescanActivity()
                }
            }
        }
        let (wanted, want) = AsyncStream.makeStream(of: Bool.self)
        state.gitHubWanted = want
        Task { for await wanted in wanted { await coordinator.setGitHubWanted(wanted) } }
        Task {
            state.apply(enabled: await registry.enabledProviders())
            await coordinator.start()
        }
        return state
    }

    /// Refresh and Retry (FR-32).
    func refresh() {
        Task { await coordinator?.refreshNow() }
    }

    /// SPEC §12 "popover opened".
    func popoverOpened() {
        Task { await coordinator?.popoverOpened() }
        rescanActivity()
    }

    private func rescanActivity() {
        for activity in activities.values { Task { await activity.source.rescan() } }
    }

    /// FR-2, US-12: a disabled provider watches nothing and the coordinator skips it; its group leaves the popover.
    /// Enabling it shows its cached snapshot and runs what is due.
    // ponytail: a probe already running when the provider is disabled still finishes (at most 30 s, FR-7).
    func setEnabled(_ id: ProviderID, _ enabled: Bool) async {
        guard let registry, let coordinator else { return }
        await registry.setEnabled(id, enabled)
        apply(enabled: await registry.enabledProviders())
        if enabled { await coordinator.start() }
    }

    /// The one place the registry's enabled set takes effect: the setting, the popover and the work (FR-46).
    private func apply(enabled: [any UsageProvider]) {
        UserDefaults.standard.set(enabled.map(\.descriptor.id.rawValue), forKey: "enabledProviders")
        enabledIDs = Set(enabled.map(\.descriptor.id))
        applyDemand()
    }

    /// The sources that are on: the enabled providers and GitHub.
    // ponytail: GitHub always on and the menu bar using nothing until T-5.14 and T-5.10 add the switch and the modes.
    private var on: Set<BlockID> { Set(enabledIDs.map(BlockID.provider)).union([.github]) }

    /// FR-46: activity is watched as long as a task consumes its stream (ADR-016); applying the same demand twice
    /// changes nothing.
    private func applyDemand() {
        let demand = layout.demand(on: on, menuBar: [])
        for (id, activity) in activities where !demand.activity.contains(id) {
            activity.watch.cancel()
            activities[id] = nil
        }
        for provider in registry?.providers ?? [] where demand.activity.contains(provider.descriptor.id) {
            guard activities[provider.descriptor.id] == nil, let source = provider.activity else { continue }
            let watch = Task { [time] in for await report in source.reports() { self.apply(report, at: time.now) } }
            activities[provider.descriptor.id] = (source, watch)
        }
        gitHubWanted?.yield(demand.github)
    }

    /// US-12 "Delete data for this provider": its folder under the data folder, history included.
    func deleteData(of id: ProviderID) async throws {
        try await Task.detached { try JSONStore.deleteProviderData(id, in: .live) }.value
    }

    /// An interval setting changed (SPEC §11.6).
    func intervalsChanged() {
        Task { await coordinator?.intervalsChanged() }
    }

    /// SPEC §11.6 Advanced "reset caches": `state.json`'s snapshots, never history.
    func resetCaches() {
        Task { await coordinator?.resetCaches() }
    }

    /// FR-17: saves a token GitHub accepts and returns its login; GitHub then starts over with it (SPEC §12).
    func connectGitHub(token: String) async throws -> String {
        let login = try await gitHubAccount!.connect(token: token)
        await coordinator?.gitHubTokenChanged()
        return login
    }

    /// Deletes the token; GitHub's data goes with it (SPEC §12 "token changed").
    func disconnectGitHub() async throws {
        try await gitHubAccount!.disconnect()
        await coordinator?.gitHubTokenChanged()
    }

    private func apply(_ update: SourceState<GitHubReport>) {
        github = update
    }

    private func apply(_ update: SourceState<LimitsReport>, to id: ProviderID) {
        guard let index = providers.firstIndex(where: { $0.id == id }) else { return }
        providers[index].limits = update
    }

    /// No days at all, not even frozen ones: nothing on this Mac to show (SPEC §11.3, §13).
    private func apply(_ report: ActivityReport, at now: Date) {
        guard let index = providers.firstIndex(where: { $0.id == report.provider }) else { return }
        providers[index].activity =
            report.days.isEmpty
            ? .notConfigured(.noLocalData) : .loaded(Snapshot(value: report, fetchedAt: now, origin: .activity))
    }
}

extension AppState.ProviderGroupState {
    /// Before the first update every section the provider has is loading.
    init(_ provider: any UsageProvider) {
        self.init(
            descriptor: provider.descriptor, limits: provider.limits.map { _ in .loading(previous: nil) },
            activity: provider.activity.map { _ in .loading(previous: nil) })
    }
}

/// An interval setting in minutes (SPEC §10.7); `nil` keeps the policy's default.
nonisolated private func minutes(_ setting: Any?) -> Duration? {
    (setting as? Int).map { .seconds($0 * 60) }
}

extension PopoverLayout {
    /// FR-45: unset or unreadable is the default layout.
    static var stored: Self {
        get {
            (try? JSONDecoder().decode(Self.self, from: UserDefaults.standard.data(forKey: "popoverLayout") ?? Data()))
                ?? Self()
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "popoverLayout") }
    }
}

extension NotificationPlanner.Settings {
    /// FR-13, FR-14: the Settings keys of SPEC §10.7; unset keeps the planner's defaults.
    nonisolated static var stored: Self {
        get {
            let defaults = UserDefaults.standard
            var settings = Self(notifyOnReset: defaults.bool(forKey: "notifyOnReset"))
            if let thresholds = defaults.array(forKey: "notificationThresholds") as? [Int] {
                settings.thresholds = thresholds
            }
            return settings
        }
        set {
            UserDefaults.standard.set(newValue.thresholds, forKey: "notificationThresholds")
            UserDefaults.standard.set(newValue.notifyOnReset, forKey: "notifyOnReset")
        }
    }
}
