import ContribusageCore
import ContribusageGitHub
import ContribusageTestSupport
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
