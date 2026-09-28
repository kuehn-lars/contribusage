import Foundation

/// Where the app keeps its data (SPEC §10.7). A struct, not a seam: tests pass a temporary root
/// (ADR-015).
public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    /// `~/Library/Application Support/contribusage/`
    public static let live = AppPaths(
        root: .applicationSupportDirectory.appending(path: "contribusage", directoryHint: .isDirectory))

    /// `root/providers/<id>/`, everything a provider stores; "Delete data for this provider" removes it (US-12).
    public func providerFolder(_ id: ProviderID) -> URL {
        root.appending(components: "providers", id.rawValue, directoryHint: .isDirectory)
    }
}
