import ContribusageClaudeCode
import ContribusageCore
import ContribusageTestSupport
import Foundation
import Testing
import os

private let home = URL(filePath: "/Users/octocat", directoryHint: .isDirectory)
private let claude = "/Users/octocat/.local/bin/claude"
private let subscription = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 23% used · resets 4:09am (Europe/Berlin)
    """

/// A fake machine with `claude` at `.local/bin` (not on the login shell's PATH); `probe` answers `claude -p /usage`.
private func runner(
    probe: @escaping @Sendable (ProcessRequest) async throws -> ProcessResult = { _ in
        ProcessResult(exitCode: 0, stdout: subscription, stderr: "")
    }
) -> FakeProcessRunner {
    FakeProcessRunner { request in
        if request.executable.path == "/bin/zsh" { return ProcessResult(exitCode: 0, stdout: "/usr/bin\n", stderr: "") }
        guard request.executable.path == claude else { throw CocoaError(.fileNoSuchFile) }
        if request.arguments == ["--version"] { return ProcessResult(exitCode: 0, stdout: "2.1.284\n", stderr: "") }
        return try await probe(request)
    }
}

/// Probes only create their empty folder, so every test shares one root.
private let paths = AppPaths(root: FileManager.default.temporaryDirectory.appending(path: "contribusage-tests"))
private let time = FakeTimeSource(now: Date(timeIntervalSince1970: 1_790_000_000))

private func provider(
    _ runner: FakeProcessRunner, fileEvents: FakeFileEvents = FakeFileEvents(),
    fileReader: FakeFileReader = FakeFileReader()
) -> ClaudeCodeProvider {
    ClaudeCodeProvider(
        runner: runner, fileEvents: fileEvents, fileReader: fileReader, paths: paths, home: home,
        shell: URL(filePath: "/bin/zsh"), time: time)
}

private func fetch(_ runner: FakeProcessRunner) async throws -> LimitsReport {
    try await provider(runner).fetch()
}

@Test func passesConformance() async {
    let fileEvents = FakeFileEvents()
    let fileReader = FakeFileReader()
    await ProviderConformance.check(
        provider(runner(), fileEvents: fileEvents, fileReader: fileReader),
        neverFinishing: provider(
            runner { _ in
                try await Task.sleep(for: .seconds(3600))
                throw SourceError.timedOut
            }),
        failing: provider(runner { _ in throw SourceError.timedOut }),
        fileEvents: fileEvents, fileReader: fileReader,
        // FR-22, with `CLAUDE_CONFIG_DIR` as the fake login shell prints it, and the provider's own folder.
        readRoots: [
            URL(filePath: "/usr/bin/projects"), home.appending(path: ".claude/projects"),
            home.appending(path: ".config/claude/projects"), paths.providerFolder(.claudeCode),
        ]
    )
}

@Test func probesAsFR7Says() async throws {
    let fake = runner()
    let report = try await fetch(fake)
    #expect(report.windows.map(\.label) == ["Current session"])
    let probe = try #require(fake.requests.last)
    #expect(probe.executable.path == claude)
    #expect(probe.arguments == ["-p", "/usage", "--no-session-persistence"])
    #expect(probe.workingDirectory.path.hasSuffix("/providers/claude-code/probe"))
    #expect(FileManager.default.fileExists(atPath: probe.workingDirectory.path))
    #expect(probe.environment?["PATH"] == "/usr/bin")
    #expect(probe.timeout == .seconds(30))
}

/// The probe runs before the first snapshot write, so it creates the app folder and must make it owner-only (SPEC §10.7).
@Test func createsTheProbeFolderOwnerOnly() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try await ClaudeCodeProvider(
        runner: runner(), fileEvents: FakeFileEvents(), fileReader: FakeFileReader(), paths: AppPaths(root: root),
        home: home, shell: URL(filePath: "/bin/zsh"), time: time
    ).fetch()
    let attributes = try FileManager.default.attributesOfItem(atPath: root.path(percentEncoded: false))
    #expect(attributes[.posixPermissions] as? Int == 0o700)
}

@Test func cachesTheLocatedClaude() async throws {
    let fake = runner()
    let provider = provider(fake)
    #expect(await provider.detectAvailability() == .available(version: "2.1.284"))
    _ = try await provider.fetch()
    _ = try await provider.fetch()
    #expect(fake.requests.filter { $0.arguments == ["--version"] }.count == 1)
}

@Test func reResolvesWhenTheCachedPathStopsWorking() async throws {
    let launches = OSAllocatedUnfairLock(initialState: 0)
    let fake = runner { _ in
        // The first probe finds the binary gone, as after an update that moved it.
        if launches.withLock({
            $0 += 1
            return $0
        }) == 1 {
            throw CocoaError(.fileNoSuchFile)
        }
        return ProcessResult(exitCode: 0, stdout: subscription, stderr: "")
    }
    #expect(try await fetch(fake).windows.count == 1)
    #expect(fake.requests.filter { $0.executable.path == "/bin/zsh" }.count == 2)
}

@Test func joinsARunningProbe() async throws {
    let fake = runner { _ in
        try await Task.sleep(for: .milliseconds(200))
        return ProcessResult(exitCode: 0, stdout: subscription, stderr: "")
    }
    let provider = provider(fake)
    async let first = provider.fetch()
    async let second = provider.fetch()
    _ = try await (first, second)
    #expect(fake.requests.filter { $0.arguments.first == "-p" }.count == 1)
}

@Test func reportsAMissingClaude() async {
    let missing = FakeProcessRunner { _ in throw CocoaError(.fileNoSuchFile) }
    await #expect(throws: SourceError.toolNotFound) { try await fetch(missing) }
    #expect(await provider(missing).detectAvailability() == .notInstalled)
}

@Test func passesTimeoutsThrough() async {
    await #expect(throws: SourceError.timedOut) { try await fetch(runner { _ in throw SourceError.timedOut }) }
}

/// SPEC §13 and FR-9 for what a finished probe printed.
@Test(arguments: [
    (ProcessResult(exitCode: 1, stdout: "", stderr: "Please run /login\n"), SourceError.notLoggedIn),
    (ProcessResult(exitCode: 1, stdout: "Not logged in\n", stderr: ""), .notLoggedIn),
    (ProcessResult(exitCode: 2, stdout: "", stderr: "boom\n"), .processFailed(exitCode: 2, stderrTail: "boom\n")),
    (
        ProcessResult(exitCode: 3, stdout: "", stderr: "bad catalog index\n"),
        .processFailed(exitCode: 3, stderrTail: "bad catalog index\n")
    ),
    (
        ProcessResult(exitCode: 0, stdout: "Your subscription\nsomething new", stderr: ""),
        .unparseable(rawOutput: "Your subscription\nsomething new")
    ),
])
func mapsProbeResult(_ result: ProcessResult, to error: SourceError) async {
    await #expect(throws: error) { try await fetch(runner { _ in result }) }
}

@Test func locatesAgainWhenTheOverrideChanges() async throws {
    let custom = "/Users/octocat/bin/claude"
    let override = OSAllocatedUnfairLock<URL?>(initialState: nil)
    let fake = FakeProcessRunner { request in
        if request.executable.path == "/bin/zsh" { return ProcessResult(exitCode: 0, stdout: "/usr/bin\n", stderr: "") }
        guard [claude, custom].contains(request.executable.path) else { throw CocoaError(.fileNoSuchFile) }
        let output = request.arguments == ["--version"] ? "2.1.284\n" : subscription
        return ProcessResult(exitCode: 0, stdout: output, stderr: "")
    }
    let provider = ClaudeCodeProvider(
        runner: fake, fileEvents: FakeFileEvents(), fileReader: FakeFileReader(), paths: paths, home: home,
        shell: URL(filePath: "/bin/zsh"), time: time,
        override: { override.withLock { $0 } })
    _ = try await provider.fetch()
    override.withLock { $0 = URL(filePath: custom) }
    _ = try await provider.fetch()
    _ = try await provider.fetch()
    let probes = fake.requests.filter { $0.arguments.first == "-p" }.map(\.executable.path)
    #expect(probes == [claude, custom, custom])
    #expect(fake.requests.filter { $0.arguments == ["--version"] }.count == 2)
}

/// SPEC §11.6 Providers tab: the located `claude` with its executable type; the fake path is no file, hence `unknown`.
@Test func reportsTheLocatedClaude() async {
    let located = await provider(runner()).located()
    #expect(located?.executable.path == claude)
    #expect(located?.version == "2.1.284")
    #expect(located?.kind == .unknown)
    #expect(await provider(FakeProcessRunner { _ in throw CocoaError(.fileNoSuchFile) }).located() == nil)
}

/// Detection stays cheap and cannot know the plan; the probe reports it (ADR-017).
@Test func reportsAnUnsupportedPlanFromTheProbe() async throws {
    let apiKey = runner { _ in ProcessResult(exitCode: 0, stdout: "Total cost:            $0.0000\n", stderr: "") }
    let provider = provider(apiKey)
    await #expect(throws: SourceError.unsupportedPlan(note: "Total cost:            $0.0000")) {
        try await provider.fetch()
    }
    #expect(await provider.detectAvailability() == .available(version: "2.1.284"))
}
