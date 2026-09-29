import ContribusageCore
import Foundation

/// The only network destination the app contacts (SPEC §2 principle 3, §8.4.1, NFR-13).
public let gitHubGraphQLEndpoint = URL(string: "https://api.github.com/graphql")!

/// GraphQL over `HTTPTransport` (SPEC §8.4). The token is passed per call and never logged.
public struct GitHubClient: Sendable {
    private let transport: any HTTPTransport
    private let userAgent: String

    public init(transport: any HTTPTransport, version: String) {
        self.transport = transport
        userAgent = "contribusage/\(version)"
    }

    /// FR-17: the login the token belongs to.
    public func viewerLogin(token: String) async throws -> String {
        struct Viewer: Decodable { let login: String }
        struct Payload: Decodable { let viewer: Viewer }
        let payload: Payload = try await send("query { viewer { login } }", token: token)
        return payload.viewer.login
    }

    /// FR-18: the calendar from `from` to `to` (Appendix C; GitHub accepts at most one year).
    public func contributions(token: String, from: Date, to: Date) async throws -> ContributionCalendar {
        struct Day: Decodable {
            let date: String
            let contributionCount: Int
            let contributionLevel: String
        }
        struct Week: Decodable { let contributionDays: [Day] }
        struct Calendar: Decodable {
            let totalContributions: Int
            let weeks: [Week]
        }
        struct Collection: Decodable { let contributionCalendar: Calendar }
        struct Viewer: Decodable {
            let login: String
            let contributionsCollection: Collection
        }
        struct Payload: Decodable { let viewer: Viewer }
        // SPEC §8.4.1: local time with its offset, as in Appendix C.
        let format = Date.ISO8601FormatStyle(timeZoneSeparator: .colon, timeZone: .current)
        let payload: Payload = try await send(
            Self.contributionsQuery, variables: ["from": from.formatted(format), "to": to.formatted(format)],
            token: token)
        let calendar = payload.viewer.contributionsCollection.contributionCalendar
        let days = try calendar.weeks.flatMap(\.contributionDays).map { day in
            guard let level = Self.levelNames.firstIndex(of: day.contributionLevel).flatMap(ContributionLevel.init)
            else {
                throw SourceError.decoding("Unknown contribution level \(day.contributionLevel)")
            }
            return ContributionDay(date: DayKey(rawValue: day.date), count: day.contributionCount, level: level)
        }
        return ContributionCalendar(
            login: payload.viewer.login, days: days, totalContributions: calendar.totalContributions)
    }

    /// Appendix C. `restrictedContributionsCount` is fetched but not decoded until R-4 settles its meaning.
    private static let contributionsQuery = """
        query Contributions($from: DateTime!, $to: DateTime!) {
          viewer {
            login
            contributionsCollection(from: $from, to: $to) {
              restrictedContributionsCount
              contributionCalendar {
                totalContributions
                weeks { contributionDays { date contributionCount contributionLevel } }
              }
            }
          }
        }
        """

    /// Appendix C level names, in `ContributionLevel` raw value order.
    private static let levelNames = ["NONE", "FIRST_QUARTILE", "SECOND_QUARTILE", "THIRD_QUARTILE", "FOURTH_QUARTILE"]

    /// Sends one query and returns its `data`, mapping failures per SPEC §8.4.3.
    private func send<Payload: Decodable>(
        _ query: String, variables: [String: String] = [:], token: String
    ) async throws -> Payload {
        var request = URLRequest(url: gitHubGraphQLEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GraphQLBody(query: query, variables: variables))
        let (body, response) = try await transport.send(request)
        if response.statusCode == 401 { throw SourceError.unauthorized }
        let failure: SourceError
        if (200..<300).contains(response.statusCode) {
            let envelope: GraphQLEnvelope<Payload>
            do { envelope = try JSONDecoder().decode(GraphQLEnvelope<Payload>.self, from: body) } catch {
                throw SourceError.decoding(error.localizedDescription)
            }
            if let data = envelope.data, envelope.errors == nil { return data }
            failure = .decoding(envelope.errors?.first?.message ?? "No data in response")
        } else {
            failure = .http(status: response.statusCode)
        }
        // ADR-020: any failure with an exhausted budget (200 with `errors`, 403, 429) waits for the reset.
        if response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0",
            let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init)
        {
            throw SourceError.rateLimited(until: Date(timeIntervalSince1970: reset))
        }
        throw failure
    }
}

private struct GraphQLBody: Encodable {
    let query: String
    let variables: [String: String]
}

private struct GraphQLEnvelope<Payload: Decodable>: Decodable {
    struct Message: Decodable { let message: String }
    let data: Payload?
    let errors: [Message]?
}
