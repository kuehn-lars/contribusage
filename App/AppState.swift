import ContribusageCore
import ContribusageGitHub
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

    init(providers: [ProviderGroupState], github: SourceState<GitHubReport>) {
        self.providers = providers
        self.github = github
    }
}
