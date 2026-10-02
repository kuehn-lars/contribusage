import Foundation

/// A JSON file the app persists (SPEC §10.7), stored as `{"schemaVersion": n, "value": …}`.
public protocol PersistedFile: Codable, Sendable {
    static var schemaVersion: Int { get }
}

public enum PersistenceError: Error, Equatable {
    /// The file holds another version. It is left untouched: a cache ignores the error and is overwritten on the next
    /// write, `history.json` is backed up and migrated by its owner and never discarded.
    case unsupportedSchemaVersion(Int)
}

/// Versioned, atomic JSON files (SPEC §10.7, ADR-005).
public enum JSONStore {
    /// `nil` when the file does not exist. Every caller names its reader: a provider passes its own `fileReader` (SPEC
    /// §16.4), so no read slips past the conformance check by default.
    public static func read<Value: PersistedFile>(
        _: Value.Type, from file: URL, using fileReader: any FileReading
    ) throws -> Value? {
        let data: Data
        do {
            data = try fileReader.contents(of: file)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        let version = try JSONDecoder().decode(Header.self, from: data).schemaVersion
        guard version == Value.schemaVersion else { throw PersistenceError.unsupportedSchemaVersion(version) }
        return try JSONDecoder().decode(Envelope<Value>.self, from: data).value
    }

    /// Creates `folder` and its missing parents owner-only (`0700`). Every folder under `AppPaths.root` is made here,
    /// whichever write comes first. An existing folder keeps its mode.
    public static func createFolder(_ folder: URL) throws {
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    /// Creates missing folders owner-only, then replaces the file atomically.
    public static func write<Value: PersistedFile>(_ value: Value, to file: URL) throws {
        try createFolder(file.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try encoder.encode(Envelope(schemaVersion: Value.schemaVersion, value: value)).write(to: file, options: .atomic)
    }

    /// "Delete data for this provider" (US-12): removes `providers/<id>/` and nothing else; a missing folder is fine.
    public static func deleteProviderData(_ id: ProviderID, in paths: AppPaths) throws {
        do {
            try FileManager.default.removeItem(at: paths.providerFolder(id))
        } catch CocoaError.fileNoSuchFile {}
    }

    private struct Header: Decodable { let schemaVersion: Int }

    private struct Envelope<Value: Codable>: Codable {
        let schemaVersion: Int
        let value: Value
    }
}
