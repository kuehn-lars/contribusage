import ContribusageCore
import ContribusageGitHub
import Foundation
import Observation

/// The view model (SPEC §9.2): one `SourceState` per provider capability and one for GitHub.
@Observable final class AppState {
    /// One popover group (FR-4). Only enabled providers get one, in registry order.
    struct ProviderGroupState: Identifiable {
        let descriptor: ProviderDescriptor
        /// `nil` when the provider lacks the capability.
        var limits: SourceState<LimitsReport>?
        var activity: SourceState<ActivityReport>?
        var id: ProviderID { descriptor.id }
    }

    var providers: [ProviderGroupState]
    var github: SourceState<GitHubReport>
    /// `nil` in previews.
    @ObservationIgnored private var coordinator: RefreshCoordinator<GitHubReport>?
    /// `nil` in previews, which never open Settings.
    @ObservationIgnored private var gitHubAccount: GitHubAccount?
    @ObservationIgnored private var conditions: SystemConditions?
    /// The enabled providers' activity sources, rescanned on popover open and wake (SPEC §12).
    @ObservationIgnored private var activities: [any ActivitySource] = []

    init(providers: [ProviderGroupState], github: SourceState<GitHubReport>) {
        self.providers = providers
        self.github = github
    }

    /// The running app: the registered providers and GitHub on the coordinator, fed by the Mac's conditions (SPEC §12).
    static func live() -> AppState {
        let state = AppState(providers: [], github: .loading(previous: nil))
        // FR-16: Keychain service `<bundle id>.github`. Both Info.plist keys come from the build settings.
        let gitHubAccount = GitHubAccount(
            secrets: KeychainSecretStore(service: Bundle.main.bundleIdentifier! + ".github"),
            client: GitHubClient(
                transport: URLSessionTransport(),
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String))
        state.gitHubAccount = gitHubAccount
        let time = SystemTimeSource()
        let defaults = UserDefaults.standard
        let enabledIDs = defaults.stringArray(forKey: "enabledProviders").map { Set($0.map(ProviderID.init)) }
        let registry = ProviderRegistry(
            providers: ProviderRegistration.all(time: time), enabledIDs: enabledIDs, time: time)
        let github = RefreshCoordinator<GitHubReport>.Job(
            policy: GitHubReport.policy, origin: .github,
            // ponytail: the Mac's calendar defines GitHub's today until R-4 names the zone GitHub counts in (ADR-021).
            fetch: { try await gitHubAccount.report(now: time.now, calendar: .current) },
            onUpdate: { [weak state] update in await state?.apply(update) })
        // FR-13, FR-14: the Settings keys of SPEC §10.7, read before every plan.
        let notifications = RefreshCoordinator<GitHubReport>.Notifications(
            settings: {
                let defaults = UserDefaults.standard
                var settings = NotificationPlanner.Settings(notifyOnReset: defaults.bool(forKey: "notifyOnReset"))
                if let thresholds = defaults.array(forKey: "notificationThresholds") as? [Int] {
                    settings.thresholds = thresholds
                }
                return settings
            }, deliver: NotificationDelivery.shared.deliver)
        let coordinator = RefreshCoordinator(
            registry: registry, paths: .live, time: time, github: github, notifications: notifications
        ) { [weak state] id, update in await state?.apply(update, to: id) }
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
        Task {
            let enabled = await registry.enabledProviders()
            defaults.set(enabled.map(\.descriptor.id.rawValue), forKey: "enabledProviders")  // FR-2 first-run default
            state.providers = enabled.map {
                ProviderGroupState(
                    descriptor: $0.descriptor, limits: $0.limits.map { _ in .loading(previous: nil) },
                    activity: $0.activity.map { _ in .loading(previous: nil) })
            }
            state.activities = enabled.compactMap(\.activity)
            for activity in state.activities {
                // Watching lasts as long as this loop consumes the stream (ADR-016).
                Task { for await report in activity.reports() { state.apply(report, at: time.now) } }
            }
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
        for activity in activities { Task { await activity.rescan() } }
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
