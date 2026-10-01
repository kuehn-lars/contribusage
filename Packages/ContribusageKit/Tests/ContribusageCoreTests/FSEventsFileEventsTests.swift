import ContribusageCore
import Foundation
import Testing

/// The next batch, or `nil` after 10 s.
private func nextBatch(_ stream: AsyncStream<Set<URL>>) async -> Set<URL>? {
    await withTaskGroup(of: Set<URL>?.self) { group in
        group.addTask { await stream.first { _ in true } }
        group.addTask {
            try? await Task.sleep(for: .seconds(10))
            return nil
        }
        defer { group.cancelAll() }
        return await group.next() ?? nil
    }
}

/// FR-27, T-4.5, against the real file system. The root does not exist yet (`~/.claude/projects` may appear
/// after the app starts); creating it and a project folder reports only the file, by its real path
/// (`/private/var/…`), as FSEvents does.
@Test func fsEventsFileEventsReportsFilesUnderARootCreatedLater() async throws {
    let temporary = try #require(realpath(NSTemporaryDirectory(), nil))
    defer { free(temporary) }
    let parent = URL(filePath: String(cString: temporary)).appending(path: "contribusage-\(UUID())")
    defer { try? FileManager.default.removeItem(at: parent) }
    let root = parent.appending(path: "projects", directoryHint: .isDirectory)
    let stream = FSEventsFileEvents().changes(in: [root], debounce: .milliseconds(200))

    let file = root.appending(path: "project/a.jsonl")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{}\n".utf8).write(to: file)

    #expect(await nextBatch(stream) == [file])
}
