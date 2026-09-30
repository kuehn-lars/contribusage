import ContribusageCore
import ContribusageGitHub
import ContribusageTestSupport
import Foundation
import Testing

private func account(status: Int, body: String, secrets: FakeSecretStore) -> GitHubAccount {
    GitHubAccount(secrets: secrets, client: GitHubClient(transport: respond(status, body), version: "1.0"))
}

/// FR-16, FR-17: a token GitHub accepts is saved under `token` and resolves to its login.
@Test func connectSavesAValidatedToken() async throws {
    let secrets = FakeSecretStore()
    let login = try await account(status: 200, body: #"{"data":{"viewer":{"login":"octocat"}}}"#, secrets: secrets)
        .connect(token: "ghp_x")
    #expect(login == "octocat")
    #expect(try secrets.read("token") == "ghp_x")
}

/// SPEC §14: a token GitHub rejects is never saved, and a saved one survives the rejected attempt.
@Test func connectKeepsARejectedTokenOut() async throws {
    let secrets = FakeSecretStore()
    try secrets.write("token", value: "old")
    await #expect(throws: SourceError.unauthorized) {
        try await account(status: 401, body: "{}", secrets: secrets).connect(token: "bad")
    }
    #expect(try secrets.read("token") == "old")
}

@Test func disconnectDeletesTheToken() async throws {
    let secrets = FakeSecretStore()
    try secrets.write("token", value: "ghp_x")
    try await account(status: 200, body: "{}", secrets: secrets).disconnect()
    #expect(try secrets.read("token") == nil)
}

/// FR-18, FR-19, SPEC §8.4.1: without a token nothing is sent; with one, the year from the start of the local day
/// 364 days ago up to now, with the statistics for `calendar`'s today.
@Test func reportFetchesTheYearUpToNow() async throws {
    let secrets = FakeSecretStore()
    let transport = respond(200, try fixture("calendar"))
    let account = GitHubAccount(secrets: secrets, client: GitHubClient(transport: transport, version: "1.0"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let now = try Date("2026-09-29T15:00:00+09:00", strategy: .iso8601)

    await #expect(throws: SourceError.tokenMissing) { try await account.report(now: now, calendar: calendar) }
    #expect(transport.requests.isEmpty)

    try secrets.write("token", value: "ghp_x")
    let report = try await account.report(now: now, calendar: calendar)
    let variables = try sent(#require(transport.requests.first)).variables
    #expect(
        try Date(#require(variables["from"]), strategy: .iso8601)
            == Date("2025-09-30T00:00:00+09:00", strategy: .iso8601))
    #expect(try Date(#require(variables["to"]), strategy: .iso8601) == now)
    #expect(report.calendar.login == "octocat")
    #expect(report.stats.today == 28)
}
