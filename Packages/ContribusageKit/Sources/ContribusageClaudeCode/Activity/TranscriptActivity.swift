import ContribusageCore
import Foundation
import os

private let log = Logger(subsystem: "contribusage", category: "activity")

/// Claude Code's activity source (SPEC §8.3): the transcripts under the FR-22 roots, read incrementally (FR-26),
/// de-duplicated across files (FR-24) and merged with the frozen history (FR-29).
actor TranscriptActivity: ActivitySource {
    private let fileEvents: any FileEvents
    private let runner: any ProcessRunning
    private let home: URL
    private let shell: URL
    private let probeFolder: URL
    private let paths: AppPaths
    private let time: any TimeSource
    private let calendar: Calendar

    /// Resolved on the first subscription; the login shell's `CLAUDE_CONFIG_DIR` does not change while the app runs.
    private var roots: [URL]?
    private var reader = IncrementalJSONLReader()
    /// Per transcript its decoded lines and how many it could not decode. The aggregate is rebuilt from all of them,
    /// because a key repeats across files (resumed sessions) and a file can shrink or vanish.
    // ponytail: every usage line stays in memory; drop lines older than the live window if NFR-2 is at risk (T-4.7).
    private var files: [URL: Transcript] = [:]
    /// `nil` when `history.json` is unreadable: it stays on disk untouched and the report shows live days only.
    private lazy var history: HistoryStore? = {
        do {
            return try HistoryStore(provider: .claudeCode, paths: paths)
        } catch {
            log.error("history unreadable, left untouched: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()
    private var streams: [UUID: AsyncStream<ActivityReport>.Continuation] = [:]

    private struct Transcript {
        var lines: [TranscriptLine] = []
        var skipped = 0
    }

    init(
        fileEvents: any FileEvents, runner: any ProcessRunning, home: URL, shell: URL, probeFolder: URL,
        paths: AppPaths, time: any TimeSource, calendar: Calendar
    ) {
        self.fileEvents = fileEvents
        self.runner = runner
        self.home = home
        self.shell = shell
        self.probeFolder = probeFolder
        self.paths = paths
        self.time = time
        self.calendar = calendar
    }

    nonisolated func reports() -> AsyncStream<ActivityReport> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: ActivityReport.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        // FR-27: utility QoS.
        let watching = Task(priority: .utility) {
            // Watching before the initial report, so no change after it goes unseen.
            let changes = fileEvents.changes(in: await resolveRoots(), debounce: .seconds(5))
            await subscribe(id, continuation)
            for await _ in changes { await publish() }
            // Cancelled, or the file events ended: the reports end with them. Unsubscribing here, after `subscribe`,
            // also covers a consumer that leaves while the roots are still being resolved.
            await unsubscribe(id)
            continuation.finish()
        }
        continuation.onTermination = { _ in watching.cancel() }
        return stream
    }

    func rescan() async { publish() }

    /// Registers the stream and sends it the initial report.
    private func subscribe(_ id: UUID, _ continuation: AsyncStream<ActivityReport>.Continuation) {
        streams[id] = continuation
        publish()
    }

    private func unsubscribe(_ id: UUID) { streams[id] = nil }

    private func publish() {
        guard let roots else { return }
        read(roots)
        let report = report()
        for continuation in streams.values { continuation.yield(report) }
    }

    private func resolveRoots() async -> [URL] {
        if let roots { return roots }
        let resolved = TranscriptFiles.roots(home: home, configDir: await configDir())
        roots = resolved
        return resolved
    }

    /// `CLAUDE_CONFIG_DIR` from the login shell, which a Finder-started app does not inherit (SPEC §20). Profile
    /// scripts may print first, so the value is the last line; only an absolute path counts.
    private func configDir() async -> URL? {
        let request = ProcessRequest(
            executable: shell, arguments: ["-lc", #"printf '%s\n' "$CLAUDE_CONFIG_DIR""#], workingDirectory: home,
            environment: nil, timeout: .seconds(10))
        guard let result = try? await runner.run(request), result.exitCode == 0,
            let line = result.stdout.split(whereSeparator: \.isNewline).last, line.hasPrefix("/")
        else { return nil }
        return URL(filePath: String(line), directoryHint: .isDirectory)
    }

    /// Brings `files` up to date: new lines appended, rescanned files from scratch, vanished files dropped.
    // ponytail: opens every transcript on each change; read only the changed ones if T-4.7 measures it too slow.
    private func read(_ roots: [URL]) {
        let listed = TranscriptFiles.files(in: roots, excludingProjectOf: probeFolder)
        for url in Set(listed).union(files.keys) {
            do {
                guard let appended = try reader.read(url) else {
                    files[url] = nil
                    continue
                }
                var file = appended.isRescan ? Transcript() : files[url, default: Transcript()]
                for line in appended.lines {
                    do {
                        if let decoded = try TranscriptLine.decode(line) { file.lines.append(decoded) }
                    } catch {
                        file.skipped += 1
                    }
                }
                files[url] = file
            } catch {
                // SPEC §13: retried on the next change.
                log.error("transcript unreadable: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The days of all transcripts, de-duplicated across files, merged with the frozen history.
    private func report() -> ActivityReport {
        var aggregator = TranscriptAggregator(calendar: calendar)
        // Path order, so the same files always give the same counts when duplicates disagree.
        for (_, file) in files.sorted(by: { $0.key.path < $1.key.path }) {
            for line in file.lines { aggregator.add(line) }
        }
        let live = aggregator.days()
        var days = live
        do {
            days = try history?.merge(live, now: time.now, calendar: calendar) ?? live
        } catch {
            // SPEC §13 disk write failure: show the live days, freeze again on the next change.
            log.error("history not saved: \(error.localizedDescription, privacy: .public)")
        }
        return ActivityReport(
            provider: .claudeCode, days: days, skippedLines: files.values.reduce(0) { $0 + $1.skipped })
    }
}
