import ContribusageGitHub
import SwiftUI

/// SPEC §11.6. The other tabs come with their tasks.
struct SettingsView: View {
    let gitHubAccount: GitHubAccount

    var body: some View {
        TabView {
            GitHubTab(account: gitHubAccount).tabItem { Label("GitHub", systemImage: "square.grid.3x3.fill") }
        }
    }
}
