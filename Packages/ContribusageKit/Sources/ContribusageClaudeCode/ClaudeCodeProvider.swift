import ContribusageCore
import Foundation

/// The Claude Code provider (SPEC §7.5, §8.1) and its limits source, the `/usage` probe: FR-6 locate cache, FR-7 single
/// flight, P-10 and SPEC §13 error mapping. Activity comes from the transcripts (SPEC §8.3).
public actor ClaudeCodeProvider: UsageProvider, LimitsSource {
    public nonisolated var descriptor: ProviderDescriptor { .claudeCode }
    public nonisolated var limits: (any LimitsSource)? { self }
    public nonisolated let activity: (any ActivitySource)?

    private let locator: ClaudeLocator
    private let runner: any ProcessRunning
    private let probeFolder: URL
    private let time: any TimeSource
    private let override: @Sendable () -> URL?
    private var located: (claude: ClaudeLocator.Found, override: URL?)?
    private var running: Task<LimitsReport, any Error>?
    /// What the last probe printed, for diagnostics; `nil` until a probe finishes.
    private var lastProbe: ProcessResult?

    /// `override` reads the `provider.claude-code.pathOverride` setting on every resolution. `calendar` defines the
    /// local day of activity.
    public init(
        runner: any ProcessRunning, fileEvents: any FileEvents, fileReader: any FileReading, paths: AppPaths,
        home: URL, shell: URL, time: any TimeSource, calendar: Calendar = .autoupdatingCurrent,
        override: @escaping @Sendable () -> URL? = { nil }
    ) {
        locator = ClaudeLocator(runner: runner, home: home, shell: shell)
        self.runner = runner
        probeFolder = paths.providerFolder(.claudeCode).appending(path: "probe", directoryHint: .isDirectory)
        self.time = time
        self.override = override
        activity = TranscriptActivity(
            fileEvents: fileEvents, fileReader: fileReader, runner: runner, home: home, shell: shell,
            probeFolder: probeFolder, paths: paths, time: time, calendar: calendar)
    }

    /// FR-3: only the first call runs processes. Never `notSignedIn`: a logged out CLI prints the same as API key
    /// billing (R-2). Never `unsupportedPlan`: only a probe can tell, and `fetch()` reports it (ADR-017).
    public func detectAvailability() async -> ProviderAvailability {
        guard let claude = await located() else { return .notInstalled }
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

    /// The cached `claude` the probe runs, located again when the override setting changed; `nil` when none is found.
    public func located() async -> ClaudeLocator.Found? {
        let override = override()
        if let located, located.override == override { return located.claude }
        guard let claude = await locator.locate(override: override) else { return nil }
        located = (claude, override)
        return claude
    }

    /// FR-36: the `claude` the probe runs, located as the Providers tab does if no probe ran yet, and the last probe.
    public func diagnostics() async -> [String] {
        var lines =
            if let claude = await located() {
                [
                    "claude: \(claude.executable.path(percentEncoded: false))", "Version: \(claude.version)",
                    "Type: \(claude.kind.diagnostics)",
                ]
            } else {
                ["claude: not found"]
            }
        if let lastProbe {
            lines += ["Last probe exit code: \(lastProbe.exitCode)", "Last /usage output:\n\(lastProbe.stdout)"]
        } else {
            lines.append("Last probe: none since launch")
        }
        return lines
    }

    private func probe() async throws -> LimitsReport {
        do {
            try JSONStore.createFolder(probeFolder)
        } catch {
            throw SourceError.io(error.localizedDescription)
        }
        let result = try await run()
        lastProbe = result
        return try report(from: result)
    }

    /// A launch failure means the path stopped working, for example after an update moved it: locate once more (FR-6).
    private func run() async throws -> ProcessResult {
        for _ in 1...2 {
            guard let claude = await located() else { throw SourceError.toolNotFound }
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
        id: .claudeCode, displayName: "Claude Code", symbolName: "terminal", heatmapHue: .orange,
        capabilities: [.limits, .activity, .insights],
        tokenCategories: Set(TokenCategory.allCases),
        limitsPolicy: SchedulePolicy(
            defaultInterval: .seconds(5 * 60), minimumInterval: .seconds(60), maximumInterval: .seconds(60 * 60),
            staleAfter: .seconds(30 * 60), manualFloor: .seconds(30), needsNetwork: true),
        toolText: { ClaudeCodeProvider.toolText($0) })
}

extension ClaudeCodeProvider {
    /// NFR-10, ADR-033: the window labels of SPEC §8.1.4 P-4 and the insights' note, periods and request and session
    /// counts, in the app's language; anything else stays as printed. Sentences and summary parts go one by one.
    nonisolated static func toolText(_ text: String, locale: Locale = .current) -> String {
        // The insights note: sentence by sentence, each keeping its period.
        let sentences = text.components(separatedBy: ". ")
        if sentences.count > 1 {
            return (sentences.dropLast().map { $0 + "." } + [sentences.last!]).map { toolText($0, locale: locale) }
                .joined(separator: " ")
        }
        if text.contains(" · ") {
            return text.components(separatedBy: " · ").map { toolText($0, locale: locale) }.joined(separator: " · ")
        }
        // Fixed texts are manual catalog keys, looked up as printed; the note's first sentence has been printed with
        // ";" and with " —". A key the catalog lacks comes back unchanged.
        let key = text.replacing(" —", with: ";")
        let fixed = localized(LocalizedStringResource(String.LocalizationValue(key), bundle: bundle), locale)
        if fixed != key { return fixed }
        let resource: LocalizedStringResource
        if let model = text.wholeMatch(of: /Current week \((.+)\)/)?.1 {
            resource = LocalizedStringResource("Current week (\(String(model)))", bundle: bundle)
        } else if let hours = text.wholeMatch(of: /Last (\d+)h/).flatMap({ Int($0.1) }) {
            resource = LocalizedStringResource("Last \(hours)h", bundle: bundle)
        } else if let days = text.wholeMatch(of: /Last (\d+)d/).flatMap({ Int($0.1) }) {
            resource = LocalizedStringResource("Last \(days)d", bundle: bundle)
        } else if let count = text.wholeMatch(of: /(\d+) requests?/).flatMap({ Int($0.1) }) {
            resource = LocalizedStringResource("\(count) requests", bundle: bundle)
        } else if let count = text.wholeMatch(of: /(\d+) sessions?/).flatMap({ Int($0.1) }) {
            resource = LocalizedStringResource("\(count) sessions", bundle: bundle)
        } else {
            return text
        }
        return localized(resource, locale)
    }

    private nonisolated static func localized(_ resource: LocalizedStringResource, _ locale: Locale) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }

    /// The target's resource bundle, which holds the String Catalog.
    nonisolated static let resources = Bundle.module.bundleURL
    private nonisolated static var bundle: LocalizedStringResource.BundleDescription { .atURL(resources) }
}
