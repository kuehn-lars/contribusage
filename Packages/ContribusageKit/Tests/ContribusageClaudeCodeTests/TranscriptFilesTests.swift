import Foundation
import Testing

@testable import ContribusageClaudeCode

private func makeFiles(_ paths: [String], in folder: URL) throws {
    for path in paths {
        let url = folder.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }
}

/// FR-22: config dir first, then the two defaults; missing folders and duplicates are left out.
@Test func rootsInOrderExistingOnly() throws {
    let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: home) }
    try makeFiles([".claude/projects/x.jsonl", "custom/projects/x.jsonl"], in: home)
    let custom = home.appending(path: "custom")
    let claude = home.appending(path: ".claude")
    let projects = { (base: URL) in base.appending(path: "projects", directoryHint: .isDirectory).standardizedFileURL }

    #expect(TranscriptFiles.roots(home: home, configDir: custom) == [projects(custom), projects(claude)])
    #expect(TranscriptFiles.roots(home: home, configDir: claude) == [projects(claude)])
    #expect(TranscriptFiles.roots(home: home, configDir: nil) == [projects(claude)])
}

/// FR-22, FR-28: `**/*.jsonl`, nested folders included, the probe folder's project directory excluded.
@Test func filesSkipTheProbeProject() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    // Claude Code encodes every character outside [a-zA-Z0-9] as "-", the space included (R-3).
    // A directory URL, as the provider builds it: its path ends in "/", which the directory name does not.
    let probe = URL(filePath: "/Users/octocat/Library/Application Support/contribusage/providers/claude-code/probe/")
    try makeFiles(
        [
            "-Users-octocat-Library-Application-Support-contribusage-providers-claude-code-probe/s.jsonl",
            "-Users-octocat-work/s1.jsonl", "-Users-octocat-work/s1/subagents/a.jsonl", "-Users-octocat-work/notes.txt",
        ], in: root)

    let files = TranscriptFiles.files(in: [root], excludingProjectOf: probe)
    #expect(files.map(\.lastPathComponent).sorted() == ["a.jsonl", "s1.jsonl"])
}
