/// Stable identifier of a provider. Persistence folders (`providers/<id>/`) and settings keys
/// (`provider.<id>.<key>`) are derived from it, so a raw value never changes once shipped (SPEC §10.2, §10.7).
/// As a dictionary key it encodes as a JSON object key (`state.json`).
public struct ProviderID: RawRepresentable, Hashable, Sendable, Codable, CodingKeyRepresentable {
    /// Lowercase, `[a-z0-9-]`.
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}
