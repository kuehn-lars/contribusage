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
        /// FR-38: the insights the group can show; the Popover tab decides whether it does (FR-44).
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
    /// FR-43: off sends no requests and hides GitHub's block; the token stays. Saved under `githubEnabled`.
    var gitHubEnabled = UserDefaults.standard.object(forKey: "githubEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(gitHubEnabled, forKey: "githubEnabled")
            applyDemand()
        }
    }
    /// FR-12: saved under `menuBarMode`; the label shows `resolvedMenuBarMode`. A GitHub mode makes GitHub fetch (FR-46).
    var menuBarMode = UserDefaults.standard.string(forKey: "menuBarMode").flatMap(MenuBarMode.init) ?? .primary {
        didSet {
            UserDefaults.standard.set(menuBarMode.rawValue, forKey: "menuBarMode")
            applyDemand()
        }
    }
    /// FR-12: saved under `menuBarProvider`; `shownMenuBarProvider` is the one in use.
    var menuBarProvider = UserDefaults.standard.string(forKey: "menuBarProvider").map(ProviderID.init) {
        didSet {
            UserDefaults.standard.set(menuBarProvider?.rawValue, forKey: "menuBarProvider")
            applyDemand()
        }
    }
    /// FR-51: saved under `menuBarStyle`; the heatmap style makes the label's source fetch its activity (FR-46).
    var menuBarStyle = UserDefaults.standard.string(forKey: "menuBarStyle").flatMap(MenuBarStyle.init) ?? .prompt {
        didSet {
            UserDefaults.standard.set(menuBarStyle.rawValue, forKey: "menuBarStyle")
            applyDemand()
        }
    }
    /// FR-51: saved under `menuBarTint`.
    var menuBarTint = UserDefaults.standard.string(forKey: "menuBarTint").flatMap(MenuBarTint.init) ?? .provider {
        didSet { UserDefaults.standard.set(menuBarTint.rawValue, forKey: "menuBarTint") }
    }
    /// FR-51: the custom tint as `RRGGBB`, saved under `menuBarColor`; a warm clay until the user picks one.
    var menuBarColor = UserDefaults.standard.string(forKey: "menuBarColor") ?? "D97757" {
        didSet { UserDefaults.standard.set(menuBarColor, forKey: "menuBarColor") }
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

    /// The popover's blocks in order (FR-44, FR-47); Copy follows them (FR-42).
    // ponytail: the heatmap counts as on for a provider without daily data, which has no layer (FR-48); move the rule
    // into `PopoverLayout` when such a provider exists (T-5.17).
    var blocks: [BlockID] { layout.blocks(registered: providers.map(\.id), on: on) }

    /// FR-48: the heatmap's sources in block order; a provider has a layer when it has daily data.
    var heatmapSources: [BlockID] {
        let sources = providers.filter { $0.descriptor.capabilities.contains(.activity) }.map(\.id)
        return layout.heatmapLayers(sources: sources, on: on)
    }

    /// A registered provider's group; `providers` holds every registered one, so a block or layout ID always has one.
    func group(_ id: ProviderID) -> ProviderGroupState { providers.first { $0.id == id }! }

    /// FR-47: whether a block's source is on.
    func isOn(_ block: BlockID) -> Bool { layout.isOn(block, on: on) }

    /// FR-12: the enabled providers with limits, in registry order.
    var menuBarProviders: [ProviderGroupState] {
        providers.filter { enabledIDs.contains($0.id) && $0.limits != nil }
    }

    /// FR-12: the modes Settings offers, those whose source is on.
    var menuBarModes: [MenuBarMode] {
        MenuBarMode.offered(providers: !menuBarProviders.isEmpty, github: gitHubEnabled)
    }

    var resolvedMenuBarMode: MenuBarMode { menuBarMode.resolved(among: menuBarModes) }

    /// FR-12: the saved menu bar provider while it is on, else the first enabled one.
    var shownMenuBarProvider: ProviderID? {
        let ids = menuBarProviders.map(\.id)
        return ids.first { $0 == menuBarProvider } ?? ids.first
    }

    /// SPEC §11.1; hiding a section changes nothing here (FR-46).
    func menuBarLabel(at now: Date) -> MenuBarLabel {
        let github = github.snapshot.map {
            (today: $0.value.stats.today, isStale: $0.isStale(at: now, after: GitHubReport.policy.staleAfter))
        }
        return MenuBarLabel(
            mode: resolvedMenuBarMode, provider: shownMenuBarProvider,
            providers: menuBarProviders.map { ($0.descriptor, $0.limits?.snapshot) }, github: github, at: now)
    }

    /// FR-46: what the menu bar label uses: GitHub's value, and the activity its heatmap styles draw (FR-51).
    // ponytail: read when a setting changes, so a heatmap does not follow `highest` to another provider's window as
    // limits arrive; re-apply the demand on new limits once a second provider exists (T-5.17).
    private var menuBarSources: Set<BlockID> {
        let heatmap = menuBarHeatmapSources(menuBarLabel(at: time.now), style: menuBarStyle)
        return Set(heatmap).union(resolvedMenuBarMode.usesGitHub ? [.github] : [])
    }

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

    /// The sources that are on: the enabled providers and GitHub while switched on (FR-2, FR-43).
    private var on: Set<BlockID> {
        Set(enabledIDs.map(BlockID.provider)).union(gitHubEnabled ? [.github] : [])
    }

    /// FR-46: activity is watched as long as a task consumes its stream (ADR-016); applying the same demand twice
    /// changes nothing.
    private func applyDemand() {
        let demand = layout.demand(on: on, menuBar: menuBarSources)
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
