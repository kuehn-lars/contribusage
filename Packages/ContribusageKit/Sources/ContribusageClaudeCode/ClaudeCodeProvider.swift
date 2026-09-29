import ContribusageCore
import Foundation

/// The Claude Code provider (SPEC §7.5, §8.1) and its limits source, the `/usage` probe: FR-6 locate cache, FR-7 single
/// flight, P-10 and SPEC §13 error mapping. Activity arrives with phase 4.
public actor ClaudeCodeProvider: UsageProvider, LimitsSource {
    public nonisolated var descriptor: ProviderDescriptor { .claudeCode }
    public nonisolated var limits: (any LimitsSource)? { self }
    public nonisolated var activity: (any ActivitySource)? { nil }

    private let locator: ClaudeLocator
    private let runner: any ProcessRunning
    private let probeFolder: URL
    private let time: any TimeSource
    private let override: @Sendable () -> URL?
    private var located: (claude: ClaudeLocator.Found, override: URL?)?
    private var running: Task<LimitsReport, any Error>?

    /// `override` reads the `provider.claude-code.pathOverride` setting on every resolution.
    public init(
        runner: any ProcessRunning, paths: AppPaths, home: URL, shell: URL, time: any TimeSource,
        override: @escaping @Sendable () -> URL? = { nil }
    ) {
        locator = ClaudeLocator(runner: runner, home: home, shell: shell)
        self.runner = runner
        probeFolder = paths.providerFolder(.claudeCode).appending(path: "probe", directoryHint: .isDirectory)
        self.time = time
        self.override = override
    }

    /// FR-3: only the first call runs processes. Never `notSignedIn`: a logged out CLI prints the same as API key
    /// billing (R-2). Never `unsupportedPlan`: only a probe can tell, and `fetch()` reports it (ADR-017).
    public func detectAvailability() async -> ProviderAvailability {
        guard let claude = await locate() else { return .notInstalled }
        return .available(version: claude.version)
    }

    /// Joins the running probe if there is one (FR-7).
    public func fetch() async throws -> LimitsReport {
        // ponytail: cancelling one joined caller cancels the probe for all; count waiters if joins become common.
        let task =
            running
            ?? Task {
                defer { running = nil }
                return try await probe()
            }
        running = task
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Empty until the status line bridge (FR-39).
    public nonisolated func pushedUpdates() -> AsyncStream<LimitsReport> { AsyncStream { $0.finish() } }

    /// The cached `claude`, located again when the override setting changed.
    private func locate() async -> ClaudeLocator.Found? {
        let override = override()
        if let located, located.override == override { return located.claude }
        guard let claude = await locator.locate(override: override) else { return nil }
        located = (claude, override)
        return claude
    }

    private func probe() async throws -> LimitsReport {
        do {
            try JSONStore.createFolder(probeFolder)
        } catch {
            throw SourceError.io(error.localizedDescription)
        }
        return try report(from: await run())
    }

    /// A launch failure means the path stopped working, for example after an update moved it: locate once more (FR-6).
    private func run() async throws -> ProcessResult {
        for _ in 1...2 {
            guard let claude = await locate() else { throw SourceError.toolNotFound }
            let request = ProcessRequest(
                executable: claude.executable, arguments: ["-p", "/usage", "--no-session-persistence"],
                workingDirectory: probeFolder, environment: claude.environment, timeout: .seconds(30))
            do {
                return try await runner.run(request)
            } catch let error where !(error is SourceError || error is CancellationError) {
                located = nil
            }
        }
        throw SourceError.toolNotFound
    }

    private func report(from result: ProcessResult) throws -> LimitsReport {
        guard result.exitCode == 0 else {
            // "login", "log in", "logged in"
            if (result.stdout + result.stderr).contains(/(?i)\blog(ged)? ?in\b/) { throw SourceError.notLoggedIn }
            throw SourceError.processFailed(exitCode: result.exitCode, stderrTail: String(result.stderr.suffix(500)))
        }
        let report = UsageParser.report(from: result.stdout, now: time.now)
        if let note = report.billingNote, !note.localizedCaseInsensitiveContains("subscription") {
            throw SourceError.unsupportedPlan(note: note)
        }
        guard !report.windows.isEmpty else { throw SourceError.unparseable(rawOutput: result.stdout) }
        return report
    }
}

extension ProviderDescriptor {
    /// SPEC §7.5, §8.1.4.
    fileprivate static let claudeCode = ProviderDescriptor(
        id: .claudeCode, displayName: "Claude Code", symbolName: "terminal", capabilities: [.limits, .insights],
        tokenCategories: Set(TokenCategory.allCases),
        limitsPolicy: SchedulePolicy(
            defaultInterval: .seconds(15 * 60), minimumInterval: .seconds(5 * 60), maximumInterval: .seconds(60 * 60),
            staleAfter: .seconds(30 * 60), manualFloor: .seconds(30), needsNetwork: true))
}
