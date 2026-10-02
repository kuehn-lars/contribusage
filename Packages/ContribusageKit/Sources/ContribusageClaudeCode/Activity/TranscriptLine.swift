import Foundation

/// One usage-bearing line of a Claude Code transcript (SPEC §8.3.2, FR-23).
public struct TranscriptLine: Equatable, Sendable {
    public var timestamp: Date
    public var sessionID: String?
    public var requestID: String?
    public var messageID: String?
    public var model: String
    public var isSidechain: Bool
    public var input: Int
    public var output: Int
    public var cacheWrite: Int
    public var cacheRead: Int

    /// The de-duplication key (FR-24): `message.id:requestId`, `message.id` alone, or `nil` for a line without either.
    public var key: String? { messageID.map { message in requestID.map { "\(message):\($0)" } ?? message } }

    /// `nil`: a line that carries no usage (not `assistant`, no `message.usage`, placeholder model).
    /// Throws: not JSON, or no usable `timestamp`; the caller counts it as malformed (FR-23).
    public static func decode(_ line: Data) throws -> TranscriptLine? {
        let raw = try decoder.decode(Raw.self, from: line)
        guard raw.type == "assistant", let message = raw.message, let usage = message.usage,
            let model = message.model, !(model.hasPrefix("<") && model.hasSuffix(">"))
        else { return nil }
        guard let stamp = raw.timestamp, let timestamp = date(stamp) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "timestamp"))
        }
        return TranscriptLine(
            timestamp: timestamp, sessionID: raw.sessionId, requestID: raw.requestId, messageID: message.id,
            model: model, isSidechain: raw.isSidechain ?? false, input: usage.input_tokens ?? 0,
            output: usage.output_tokens ?? 0, cacheWrite: usage.cache_creation_input_tokens ?? 0,
            cacheRead: usage.cache_read_input_tokens ?? 0)
    }

    // Built once: decode runs per line over hundreds of MB (NFR-7).
    private static let decoder = JSONDecoder()
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// Real lines carry fractional seconds ("…12:34:56.789Z"); accept both forms.
    private static func date(_ text: String) -> Date? {
        (try? Date(text, strategy: fractional)) ?? (try? Date(text, strategy: .iso8601))
    }

    // swift-format-ignore: AlwaysUseLowerCamelCase
    private struct Raw: Decodable {
        var type: String?
        var timestamp: String?
        var sessionId: String?
        var requestId: String?
        var isSidechain: Bool?
        var message: Message?

        struct Message: Decodable {
            var id: String?
            var model: String?
            var usage: Usage?
        }

        struct Usage: Decodable {
            var input_tokens: Int?
            var output_tokens: Int?
            var cache_creation_input_tokens: Int?
            var cache_read_input_tokens: Int?
        }
    }
}
