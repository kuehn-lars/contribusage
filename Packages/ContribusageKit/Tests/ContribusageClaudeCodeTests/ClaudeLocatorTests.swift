import ContribusageClaudeCode
import ContribusageCore
import ContribusageTestSupport
import Foundation
import Testing

private let home = URL(filePath: "/Users/octocat", directoryHint: .isDirectory)
private let shellPATH = "/opt/homebrew/bin:/usr/bin:/bin"

/// A fake machine: `claude --version` succeeds for `valid`; the login shell prints `shellClaude` (if
/// any) and then PATH.
private func runner(valid: Set<String>, shellClaude: String? = nil) -> FakeProcessRunner {
    FakeProcessRunner { request in
        if request.executable.path == "/bin/zsh" {
            return ProcessResult(
                exitCode: 0, stdout: (shellClaude.map { $0 + "\n" } ?? "") + shellPATH + "\n", stderr: "")
        }
        guard valid.contains(request.executable.path) else { throw CocoaError(.fileNoSuchFile) }
        return ProcessResult(exitCode: 0, stdout: "2.1.284 (Claude Code)\n", stderr: "")
    }
}

private func locate(_ runner: FakeProcessRunner, override: URL? = nil) async -> ClaudeLocator.Found? {
    await ClaudeLocator(runner: runner, home: home, shell: URL(filePath: "/bin/zsh")).locate(override: override)
}

@Test func overrideWinsWhenValid() async throws {
    let fake = runner(valid: ["/custom/claude", "/opt/homebrew/bin/claude"], shellClaude: "/opt/homebrew/bin/claude")
    let found = try #require(await locate(fake, override: URL(filePath: "/custom/claude")))
    #expect(found.executable.path == "/custom/claude")
    #expect(found.version == "2.1.284 (Claude Code)")
    #expect(fake.requests.map(\.executable.path) == ["/bin/zsh", "/custom/claude"])
    #expect(fake.requests[1].arguments == ["--version"])
    #expect(fake.requests[1].timeout == .seconds(10))
}

@Test func usesLoginShellResultAndPATH() async throws {
    let fake = runner(valid: ["/Users/octocat/.local/bin/claude"], shellClaude: "/Users/octocat/.local/bin/claude")
    let found = try #require(await locate(fake))
    #expect(found.executable.path == "/Users/octocat/.local/bin/claude")
    #expect(fake.requests[0].arguments == ["-lc", #"command -v claude; printf '%s\n' "$PATH""#])
    // An npm shim needs `node` from the login shell's PATH, for validation and for the probe.
    #expect(fake.requests[1].environment?["PATH"] == shellPATH)
    #expect(found.environment?["PATH"] == shellPATH)
}

@Test func toleratesProfileOutputAndMissingClaude() async throws {
    let fake = FakeProcessRunner { request in
        request.executable.path == "/bin/zsh"
            ? ProcessResult(exitCode: 0, stdout: "Welcome back\n" + shellPATH + "\n", stderr: "")
            : ProcessResult(
                exitCode: request.executable.path == "/usr/local/bin/claude" ? 0 : 127, stdout: "", stderr: "")
    }
    let found = try #require(await locate(fake))
    #expect(found.executable.path == "/usr/local/bin/claude")
    #expect(found.environment?["PATH"] == shellPATH)
}

@Test func fallsBackToKnownLocationsInOrder() async throws {
    let fake = runner(valid: ["/usr/local/bin/claude"])
    let found = try #require(await locate(fake))
    #expect(found.executable.path == "/usr/local/bin/claude")
    #expect(
        fake.requests.map(\.executable.path) == [
            "/bin/zsh",
            "/Users/octocat/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/Users/octocat/.npm-global/bin/claude",
            "/usr/local/bin/claude",
        ])
}

@Test func skipsInvalidCandidates() async throws {
    // Invalid override, an alias instead of a path from the shell, a candidate exiting non-zero.
    let fake = FakeProcessRunner { request in
        switch request.executable.path {
        case "/bin/zsh": ProcessResult(exitCode: 0, stdout: "alias claude=/nowhere\n" + shellPATH, stderr: "")
        case "/opt/homebrew/bin/claude": ProcessResult(exitCode: 1, stdout: "", stderr: "broken")
        case "/usr/local/bin/claude": ProcessResult(exitCode: 0, stdout: "2.0.0 (Claude Code)", stderr: "")
        default: throw CocoaError(.fileNoSuchFile)
        }
    }
    let found = try #require(await locate(fake, override: URL(filePath: "/gone/claude")))
    #expect(found.executable.path == "/usr/local/bin/claude")
    #expect(found.version == "2.0.0 (Claude Code)")
    #expect(!fake.requests.map(\.executable.path).contains("/nowhere"))
}

@Test func failingShellInheritsEnvironment() async throws {
    let fake = FakeProcessRunner { request in
        ProcessResult(exitCode: request.executable.path == "/bin/zsh" ? 1 : 0, stdout: "2.0.0", stderr: "")
    }
    let found = try #require(await locate(fake))
    #expect(found.executable.path == "/Users/octocat/.local/bin/claude")
    #expect(found.environment == nil)
}

@Test func returnsNilWhenNothingIsValid() async {
    #expect(await locate(runner(valid: [])) == nil)
}

@Test func detectsExecutableKind() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    func kind(_ bytes: [UInt8]) throws -> ClaudeLocator.ExecutableKind {
        let url = folder.appending(path: UUID().uuidString)
        try Data(bytes).write(to: url)
        return ClaudeLocator.ExecutableKind(at: url)
    }
    // Thin Mach-O 64: magic 0xfeedfacf little endian, then the CPU type.
    #expect(try kind([0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01]) == .machOArm64)
    #expect(try kind([0xcf, 0xfa, 0xed, 0xfe, 0x07, 0x00, 0x00, 0x01]) == .machOIntel)
    // Universal: magic 0xcafebabe big endian, then 20-byte slice records, CPU type first.
    let x86Slice: [UInt8] = [0x01, 0, 0, 0x07] + Array(repeating: 0, count: 16)
    let armSlice: [UInt8] = [0x01, 0, 0, 0x0c] + Array(repeating: 0, count: 16)
    #expect(try kind([0xca, 0xfe, 0xba, 0xbe, 0, 0, 0, 2] + x86Slice + armSlice) == .machOArm64)
    #expect(try kind([0xca, 0xfe, 0xba, 0xbe, 0, 0, 0, 1] + x86Slice) == .machOIntel)
    // A huge slice count must not run past the header.
    #expect(try kind([0xca, 0xfe, 0xba, 0xbe, 0xff, 0xff, 0xff, 0xff]) == .unknown)
    #expect(try kind(Array("#!/usr/bin/env node\n".utf8)) == .script)
    #expect(try kind([0, 1, 2, 3]) == .unknown)
    #expect(ClaudeLocator.ExecutableKind(at: folder.appending(path: "missing")) == .unknown)
    #expect(ClaudeLocator.ExecutableKind(at: folder) == .unknown)
}
