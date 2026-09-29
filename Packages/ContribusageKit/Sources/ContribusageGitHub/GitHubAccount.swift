import ContribusageCore

/// The saved GitHub token (FR-16): the one owner of its key and of the rule that only a validated token is saved.
public struct GitHubAccount: Sendable {
    private static let tokenKey = "token"
    private let secrets: any SecretStore
    private let client: GitHubClient

    public init(secrets: any SecretStore, client: GitHubClient) {
        self.secrets = secrets
        self.client = client
    }

    /// FR-17: saves `token` only after GitHub accepted it (SPEC §14) and returns its login.
    public func connect(token: String) async throws -> String {
        let login = try await client.viewerLogin(token: token)
        try secrets.write(Self.tokenKey, value: token)
        return login
    }

    /// `async` so the Keychain call leaves the caller's actor.
    public func disconnect() async throws {
        try secrets.delete(Self.tokenKey)
    }
}
