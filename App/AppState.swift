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
        let coordinator = RefreshCoordinator(registry: registry, paths: .live, time: time, github: github) {
            [weak state] id, update in await state?.apply(update, to: id)
        }
        state.coordinator = coordinator
        // One consumer keeps the changes in order; a task per change would not.
        let (changes, changed) = AsyncStream.makeStream(of: ScheduleConditions.self)
        state.conditions = SystemConditions { changed.yield($0) }
        Task { for await conditions in changes { await coordinator.update(conditions) } }
        Task {
            let enabled = await registry.enabledProviders()
            defaults.set(enabled.map(\.descriptor.id.rawValue), forKey: "enabledProviders")  // FR-2 first-run default
            state.providers = enabled.map {
                ProviderGroupState(descriptor: $0.descriptor, limits: $0.limits.map { _ in .loading(previous: nil) })
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
}
