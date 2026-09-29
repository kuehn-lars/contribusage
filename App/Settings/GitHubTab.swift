import ContribusageCore
import ContribusageGitHub
import SwiftUI

/// SPEC §11.6 GitHub tab. After saving, the token is never shown again, only its login (SPEC §14).
struct GitHubTab: View {
    let account: GitHubAccount
    /// The login the saved token resolved to; empty while no token is saved (SPEC §10.7).
    @AppStorage("githubLogin") private var login = ""
    @State private var token = ""
    @State private var validating = false
    @State private var error: String?

    var body: some View {
        Form {
            if login.isEmpty {
                SecureField("Token", text: $token)
                HStack {
                    Button("Validate", action: validate).disabled(trimmedToken.isEmpty || validating)
                    if validating { ProgressView().controlSize(.small) }
                }
                Link(
                    "Create a token on GitHub…",
                    destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
            } else {
                LabeledContent("Connected as @\(login)") {
                    Button("Remove token", role: .destructive, action: remove)
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }

    private var trimmedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func validate() {
        let token = trimmedToken
        validating = true
        error = nil
        Task {
            defer { validating = false }
            do {
                login = try await account.connect(token: token)
                self.token = ""
            } catch {
                self.error = (error as? SourceError)?.message(displayName: "GitHub") ?? error.localizedDescription
            }
        }
    }

    private func remove() {
        Task {
            do {
                try await account.disconnect()
                login = ""
                error = nil
            } catch {
                self.error = "Couldn't remove the token: \(error.localizedDescription)"
            }
        }
    }
}
