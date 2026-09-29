import ContribusageCore
import ContribusageGitHub
import ContribusageTestSupport
import Foundation
import Testing

/// NFR-13: the app talks to `api.github.com` over HTTPS and nowhere else.
@Test func endpointIsGitHubOverHTTPS() {
    #expect(gitHubGraphQLEndpoint.scheme == "https")
    #expect(gitHubGraphQLEndpoint.host() == "api.github.com")
}

/// A transport that answers every request with `status` and `body`.
func respond(_ status: Int, _ body: String) -> FakeHTTPTransport {
    FakeHTTPTransport { request in
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

/// FR-17: `viewer { login }` with the token as bearer.
@Test func viewerLoginSendsTokenAndReturnsLogin() async throws {
    let transport = respond(200, #"{"data":{"viewer":{"login":"octocat"}}}"#)
    let login = try await GitHubClient(transport: transport, version: "1.0").viewerLogin(token: "ghp_x")
    #expect(login == "octocat")
    let request = try #require(transport.requests.first)
    #expect(request.url == gitHubGraphQLEndpoint)
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ghp_x")
    #expect(request.value(forHTTPHeaderField: "User-Agent") == "contribusage/1.0")
    let body = try #require(
        request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
    #expect(body["query"]?.contains("viewer { login }") == true)
}

/// SPEC §8.4.3: 401 is `unauthorized`; other failures and GraphQL errors do not pass as a login.
@Test(arguments: [
    (401, "{}", SourceError.unauthorized),
    (502, "", SourceError.http(status: 502)),
    (200, #"{"errors":[{"message":"x"}]}"#, SourceError.decoding("x")),
])
func viewerLoginMapsFailures(status: Int, body: String, expected: SourceError) async {
    await #expect(throws: expected) {
        try await GitHubClient(transport: respond(status, body), version: "1.0").viewerLogin(token: "t")
    }
}
