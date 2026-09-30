import ContribusageCore
import Foundation

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

    /// FR-18, FR-19: the year up to `now` with its statistics; throws `SourceError.tokenMissing` while no token is saved.
    /// The range starts at the start of `calendar`'s day 364 days ago (SPEC §8.4.1); `calendar` also sets today and the
    /// week (ADR-021).
    public func report(now: Date, calendar: Calendar) async throws -> GitHubReport {
        guard let token = try secrets.read(Self.tokenKey) else { throw SourceError.tokenMissing }
        let from = calendar.date(byAdding: .day, value: -364, to: calendar.startOfDay(for: now))!
        let contributions = try await client.contributions(token: token, from: from, to: now)
        return GitHubReport(
            calendar: contributions, stats: ContributionStats(days: contributions.days, now: now, calendar: calendar))
    }

    /// `async` so the Keychain call leaves the caller's actor.
    public func disconnect() async throws {
        try secrets.delete(Self.tokenKey)
    }
}
