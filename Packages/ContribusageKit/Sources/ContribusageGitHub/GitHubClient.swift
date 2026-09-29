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
        struct Response: Decodable {
            struct Viewer: Decodable { let login: String }
            struct Payload: Decodable { let viewer: Viewer }
            struct Message: Decodable { let message: String }
            let data: Payload?
            let errors: [Message]?
        }
        var request = URLRequest(url: gitHubGraphQLEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["query": "query { viewer { login } }"])
        let (data, response) = try await transport.send(request)
        if response.statusCode == 401 { throw SourceError.unauthorized }
        guard (200..<300).contains(response.statusCode) else { throw SourceError.http(status: response.statusCode) }
        let decoded: Response
        do { decoded = try JSONDecoder().decode(Response.self, from: data) } catch {
            throw SourceError.decoding(error.localizedDescription)
        }
        // SPEC §8.4.3: an `errors` array with HTTP 200 is a failure.
        if let message = decoded.errors?.first?.message { throw SourceError.decoding(message) }
        guard let login = decoded.data?.viewer.login else { throw SourceError.decoding("No viewer in response") }
        return login
    }
}
