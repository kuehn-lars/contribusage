import ContribusageCore
import ContribusageGitHub
import SwiftUI

/// SPEC §11.6 GitHub tab. After saving, the token is never shown again, only its login (SPEC §14).
struct GitHubTab: View {
    @Environment(AppState.self) private var appState
    /// The login the saved token resolved to; empty while no token is saved (SPEC §10.7).
    @AppStorage("githubLogin") private var login = ""
    @State private var token = ""
    @State private var validating = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Account") {
                if login.isEmpty {
                    LabeledContent("Status", value: "Not connected")
                } else {
                    LabeledContent {
                        Button("Disconnect", role: .destructive, action: remove)
                    } label: {
                        Label(
                            "@\(login)",
                            systemImage: tokenRejected ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                        )
                        .symbolRenderingMode(.multicolor)
                        Text(tokenRejected ? "Token invalid or expired" : "Connected")
                    }
                }
            }
            Section {
                // Return in a focused field never reaches the default button, hence `onSubmit` and `validate`'s guard.
                SecureField("Token", text: $token, prompt: Text("github_pat_…"))
                    .onSubmit(validate)
            } header: {
                Text("Personal access token")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Link(
                            "Create a token on GitHub…",
                            destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                        Spacer()
                        if validating { ProgressView().controlSize(.small) }
                        Button(login.isEmpty ? "Connect" : "Replace", action: validate)
                            .keyboardShortcut(.defaultAction)
                            .disabled(trimmedToken.isEmpty || validating)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var trimmedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The saved token got a 401 (SPEC §13); only a new token clears it (SPEC §12).
    private var tokenRejected: Bool {
        if case .failed(.unauthorized, _) = appState.github { true } else { false }
    }

    private func validate() {
        let token = trimmedToken
        guard !token.isEmpty, !validating else { return }
        validating = true
        error = nil
        Task {
            defer { validating = false }
            do {
                // Replaces the saved token only once the new one validates.
                login = try await appState.connectGitHub(token: token)
                self.token = ""
            } catch {
                self.error = (error as? SourceError)?.message(displayName: "GitHub") ?? error.localizedDescription
            }
        }
    }

    private func remove() {
        Task {
            do {
                try await appState.disconnectGitHub()
                login = ""
                error = nil
            } catch {
                self.error = "Couldn't remove the token: \(error.localizedDescription)"
            }
        }
    }
}
