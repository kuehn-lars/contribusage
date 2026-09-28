import Foundation

public struct URLSessionTransport: HTTPTransport {
    /// Ephemeral: no cookies, cache or credentials on disk for responses fetched with the token.
    private let session = URLSession(configuration: .ephemeral)

    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}
