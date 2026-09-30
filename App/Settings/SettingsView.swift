import SwiftUI

/// SPEC §11.6. The other tabs come with their tasks.
struct SettingsView: View {
    var body: some View {
        TabView {
            GitHubTab().tabItem { Label("GitHub", systemImage: "square.grid.3x3.fill") }
        }
    }
}
