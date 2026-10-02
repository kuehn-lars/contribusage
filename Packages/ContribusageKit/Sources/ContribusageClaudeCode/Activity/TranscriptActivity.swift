import ContribusageCore
import Foundation
import os

private let log = Logger(subsystem: "contribusage", category: "activity")

/// Claude Code's activity source (SPEC §8.3): the transcripts under the FR-22 roots, read incrementally (FR-26),
/// de-duplicated across files (FR-24) and merged with the frozen history (FR-29).
actor TranscriptActivity: ActivitySource {
    private let fileEvents: any FileEvents
    /// Every read goes through it, so the conformance suite sees them (SPEC §16.4).
    private let fileReader: any FileReading
    private let runner: any ProcessRunning
    private let home: URL
    private let shell: URL
    private let probeFolder: URL
    private let paths: AppPaths
    private let time: any TimeSource
    private let calendar: Calendar

    /// Resolved on the first subscription; the login shell's `CLAUDE_CONFIG_DIR` does not change while the app runs.
    private var roots: [URL]?
    private var reader: IncrementalJSONLReader
    /// The live index (SPEC §8.3.4): per transcript its usage lines, one per key, and how many it could not decode. The
    /// aggregate is rebuilt from all of them, because a key repeats across files (resumed sessions) and a file can
    /// shrink or vanish.
    private var files: [URL: Transcript] = [:]
    /// `nil` when `history.json` is unreadable: it stays on disk untouched and the report shows live days only.
    private lazy var history: HistoryStore? = {
        do {
            return try HistoryStore(provider: .claudeCode, paths: paths, fileReader: fileReader)
        } catch {
            log.error("history unreadable, left untouched: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()
    private var streams: [UUID: AsyncStream<ActivityReport>.Continuation] = [:]

    struct Transcript {
        /// The first line per key, as the aggregator would count it (FR-24), without the IDs the key holds; a
        /// response repeats its usage on every line, so keeping the repeats would cost memory for nothing (NFR-2).
        var keyed: [String: TranscriptLine] = [:]
        /// Lines without a key each count as a request.
        var unkeyed: [TranscriptLine] = []
        var skipped = 0
        /// Session IDs and models, so the lines share one copy of each instead of one per line (NFR-2). Real models
        /// carry a date and pass Swift's 15-byte small-string storage, so they are interned too.
        private var strings: Set<String> = []

        mutating func add(_ line: TranscriptLine) {
            var line = intern(line)
            if let key = line.key {
                guard keyed[key] == nil else { return }
                // The key holds them.
                line.messageID = nil
                line.requestID = nil
                keyed[key] = line
            } else {
                unkeyed.append(line)
            }
        }

        /// Lines read later, interned against this file's strings: a key already here keeps its first line.
        mutating func append(_ later: Transcript) {
            for (key, line) in later.keyed where keyed[key] == nil { keyed[key] = intern(line) }
            for line in later.unkeyed { unkeyed.append(intern(line)) }
            skipped += later.skipped
        }

        private mutating func intern(_ line: TranscriptLine) -> TranscriptLine {
            var line = line
            line.sessionID = line.sessionID.map { strings.insert($0).memberAfterInsert }
            line.model = strings.insert(line.model).memberAfterInsert
            return line
        }
    }

    init(
        fileEvents: any FileEvents, fileReader: any FileReading, runner: any ProcessRunning, home: URL, shell: URL,
        probeFolder: URL, paths: AppPaths, time: any TimeSource, calendar: Calendar
    ) {
        self.fileEvents = fileEvents
        self.fileReader = fileReader
        reader = IncrementalJSONLReader(fileReader: fileReader)
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
    // ponytail: opens every transcript on each change, about 45 ms for 273 files / 520 MB in release on an M3 (ADR-026);
    // trees with many more small files cost more per pass. Read only the files in the event batch if that bites.
    private func read(_ roots: [URL]) {
        let listed = TranscriptFiles.files(in: roots, excludingProjectOf: probeFolder, fileReader: fileReader)
        for url in Set(listed).union(files.keys) {
            do {
                var appended = Transcript()
                let outcome = try reader.read(url) { line in
                    do {
                        if let decoded = try TranscriptLine.decode(line) { appended.add(decoded) }
                    } catch {
                        appended.skipped += 1
                    }
                }
                switch outcome {
                case .gone: files[url] = nil
                case .rescanned: files[url] = appended
                case .appended: files[url, default: Transcript()].append(appended)
                }
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
            for (key, line) in file.keyed { aggregator.add(line, key: key) }
            for line in file.unkeyed { aggregator.add(line) }
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
