import ContribusageCore
import ContribusageTestSupport
import Foundation
import Testing

/// SPEC §10.7 and §16.3: atomic writes, schema versions, history never discarded, provider data deletion.

private struct Sample: PersistedFile, Equatable {
    static let schemaVersion = 2
    var label: String
}

@Test func roundTripCreatesTheRootWithOwnerOnlyPermissions() throws {
    let paths = AppPaths.temporary()
    let file = paths.providerFolder(.fake).appending(path: "history.json")
    #expect(try JSONStore.read(Sample.self, from: file) == nil)

    try JSONStore.write(Sample(label: "a"), to: file)

    #expect(try JSONStore.read(Sample.self, from: file) == Sample(label: "a"))
    #expect(try String(contentsOf: file, encoding: .utf8) == #"{"schemaVersion":2,"value":{"label":"a"}}"#)
    let root = try FileManager.default.attributesOfItem(atPath: paths.root.path(percentEncoded: false))
    #expect(root[.posixPermissions] as? Int == 0o700)
}

/// An atomic write replaces the file instead of rewriting it in place: a hard link to the old file keeps the old content.
@Test func writeReplacesTheFileAtomically() throws {
    let file = AppPaths.temporary().root.appending(path: "state.json")
    try JSONStore.write(Sample(label: "old"), to: file)
    let link = file.deletingLastPathComponent().appending(path: "link.json")
    try FileManager.default.linkItem(at: file, to: link)

    try JSONStore.write(Sample(label: "new"), to: file)

    #expect(try JSONStore.read(Sample.self, from: file) == Sample(label: "new"))
    #expect(try JSONStore.read(Sample.self, from: link) == Sample(label: "old"))
}

/// Any other version throws and leaves the file alone: caches discard it by ignoring the error, `history.json` never loses it.
@Test func versionMismatchThrowsAndKeepsTheFile() throws {
    let file = AppPaths.temporary().root.appending(path: "history.json")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let newer = Data(#"{"schemaVersion":3,"value":{"label":"future"}}"#.utf8)
    try newer.write(to: file)

    #expect(throws: PersistenceError.unsupportedSchemaVersion(3)) { try JSONStore.read(Sample.self, from: file) }
    #expect(try Data(contentsOf: file) == newer)
}

@Test func deletingProviderDataRemovesOnlyThatProvidersFolder() throws {
    let paths = AppPaths.temporary()
    let other = ProviderID(rawValue: "other")
    try JSONStore.write(Sample(label: "fake"), to: paths.providerFolder(.fake).appending(path: "history.json"))
    try JSONStore.write(Sample(label: "other"), to: paths.providerFolder(other).appending(path: "history.json"))
    try JSONStore.write(Sample(label: "state"), to: paths.root.appending(path: "state.json"))

    try JSONStore.deleteProviderData(.fake, in: paths)
    try JSONStore.deleteProviderData(.fake, in: paths)  // already gone is not an error

    let fileManager = FileManager.default
    #expect(!fileManager.fileExists(atPath: paths.providerFolder(.fake).path(percentEncoded: false)))
    #expect(fileManager.fileExists(atPath: paths.providerFolder(other).path(percentEncoded: false)))
    #expect(fileManager.fileExists(atPath: paths.root.appending(path: "state.json").path(percentEncoded: false)))
}
