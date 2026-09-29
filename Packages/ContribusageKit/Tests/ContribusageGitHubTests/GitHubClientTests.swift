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

/// A transport that answers every request with `status`, `body` and `headers`.
func respond(_ status: Int, _ body: String, headers: [String: String] = [:]) -> FakeHTTPTransport {
    FakeHTTPTransport { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (Data(body.utf8), response)
    }
}

private func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/github"))
    return try String(contentsOf: url, encoding: .utf8)
}

/// The GraphQL request body as sent.
private struct Sent: Decodable {
    let query: String
    let variables: [String: String]
}

private func sent(_ request: URLRequest) throws -> Sent {
    try JSONDecoder().decode(Sent.self, from: #require(request.httpBody))
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
    #expect(try sent(request).query.contains("viewer { login }"))
}

/// FR-18, Appendix C: the calendar query with `from` and `to`, decoded into days, levels and the total.
@Test func contributionsDecodesTheCalendar() async throws {
    let transport = respond(200, try fixture("calendar"))
    let from = Date(timeIntervalSince1970: 1_759_183_200)
    let to = Date(timeIntervalSince1970: 1_790_718_000)
    let calendar = try await GitHubClient(transport: transport, version: "1.0").contributions(
        token: "ghp_x", from: from, to: to)
    #expect(calendar.login == "octocat")
    #expect(calendar.totalContributions == 1917)
    #expect(calendar.days.count == 365)
    #expect(calendar.days.first == ContributionDay(date: DayKey(rawValue: "2025-09-30"), count: 0, level: .none))
    #expect(calendar.days.last == ContributionDay(date: DayKey(rawValue: "2026-09-29"), count: 28, level: .fourth))
    #expect(Set(calendar.days.map(\.level)) == [.none, .first, .second, .third, .fourth])
    // Levels rise with the count, which pins Appendix C's name order onto `ContributionLevel`.
    let levelsByCount = calendar.days.sorted { $0.count < $1.count }.map(\.level.rawValue)
    #expect(levelsByCount == levelsByCount.sorted())

    let request = try #require(transport.requests.first)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ghp_x")
    let body = try sent(request)
    #expect(body.query.contains("contributionsCollection(from: $from, to: $to)"))
    let variables = body.variables
    #expect(try Date(#require(variables["from"]), strategy: .iso8601) == from)
    #expect(try Date(#require(variables["to"]), strategy: .iso8601) == to)
    // SPEC §8.4.1, Appendix C: local time with its offset, not UTC (R-4 checks how GitHub uses the offset).
    #expect(variables["from"]?.hasSuffix("Z") == (TimeZone.current.secondsFromGMT(for: from) == 0))
}

/// SPEC §8.4.3, ADR-020: 401 is `unauthorized`; a failure with an exhausted budget waits for `x-ratelimit-reset`,
/// whether GitHub answers 200 with `errors`, 403 or 429; with budget left it stays `decoding` or `http`.
@Test(arguments: [
    (401, "4958", SourceError.unauthorized),
    (200, "0", SourceError.rateLimited(until: Date(timeIntervalSince1970: 1_790_719_818))),
    (403, "0", SourceError.rateLimited(until: Date(timeIntervalSince1970: 1_790_719_818))),
    (429, "0", SourceError.rateLimited(until: Date(timeIntervalSince1970: 1_790_719_818))),
    (200, "4958", SourceError.decoding("API rate limit exceeded for user ID 1.")),
    (403, "4958", SourceError.http(status: 403)),
])
func sendMapsFailures(status: Int, remaining: String, expected: SourceError) async throws {
    let transport = respond(
        status, try fixture("graphql-errors"),
        headers: ["X-Ratelimit-Remaining": remaining, "X-Ratelimit-Reset": "1790719818"])
    await #expect(throws: expected) {
        try await GitHubClient(transport: transport, version: "1.0").contributions(token: "t", from: .now, to: .now)
    }
}

/// A level GitHub adds later fails loudly instead of drawing as empty.
@Test func contributionsRejectsAnUnknownLevel() async throws {
    let body = try fixture("calendar").replacingOccurrences(of: #""NONE""#, with: #""FIFTH""#)
    await #expect(throws: SourceError.decoding("Unknown contribution level FIFTH")) {
        try await GitHubClient(transport: respond(200, body), version: "1.0").contributions(
            token: "t", from: .now, to: .now)
    }
}
