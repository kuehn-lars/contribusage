import ContribusageGitHub
import Testing

/// NFR-13: the app talks to `api.github.com` over HTTPS and nowhere else.
@Test func endpointIsGitHubOverHTTPS() {
    #expect(gitHubGraphQLEndpoint.scheme == "https")
    #expect(gitHubGraphQLEndpoint.host() == "api.github.com")
}
