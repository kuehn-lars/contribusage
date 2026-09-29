import ContribusageCore
import ContribusageGitHub
import SwiftUI

@main
struct ContribusageApp: App {
    @State private var appState = AppState.live()
    /// FR-16: Keychain service `<bundle id>.github`. Both Info.plist keys come from the build settings.
    private let gitHubAccount = GitHubAccount(
        secrets: KeychainSecretStore(service: Bundle.main.bundleIdentifier! + ".github"),
        client: GitHubClient(
            transport: URLSessionTransport(),
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String))

    var body: some Scene {
        MenuBarExtra("contribusage", systemImage: "gauge.with.dots.needle.33percent") {
            PopoverView().environment(appState)
        }
        .menuBarExtraStyle(.window)
        Settings { SettingsView(gitHubAccount: gitHubAccount) }
    }
}
