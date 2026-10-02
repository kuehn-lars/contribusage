import ContribusageCore
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

/// FR-22: config dir first, then the two defaults, existing or not; duplicates are left out.
@Test func rootsInOrder() {
    let home = URL(filePath: "/Users/octocat/", directoryHint: .isDirectory)
    let projects = { (base: String) in URL(filePath: "/Users/octocat/\(base)/projects/", directoryHint: .isDirectory) }
    let defaults = [projects(".claude"), projects(".config/claude")]

    #expect(
        TranscriptFiles.roots(home: home, configDir: home.appending(path: "custom")) == [projects("custom")] + defaults)
    #expect(TranscriptFiles.roots(home: home, configDir: home.appending(path: ".claude")) == defaults)
    #expect(TranscriptFiles.roots(home: home, configDir: nil) == defaults)
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

    let files = TranscriptFiles.files(in: [root], excludingProjectOf: probe, fileReader: LiveFileReader())
    #expect(files.map(\.lastPathComponent).sorted() == ["a.jsonl", "s1.jsonl"])
}
