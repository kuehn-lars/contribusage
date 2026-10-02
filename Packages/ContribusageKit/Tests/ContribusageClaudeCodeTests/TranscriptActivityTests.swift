import ContribusageClaudeCode
import ContribusageCore
import ContribusageTestSupport
import Foundation
import Testing

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// One usage line in the shape of SPEC Appendix E.
func entry(
    _ message: String, request: String = "r", session: String = "s1", at stamp: String = "2026-09-28T10:00:00.000Z",
    input: Int = 10
) -> String {
    #"{"type":"assistant","sessionId":"\#(session)","timestamp":"\#(stamp)","requestId":"\#(request)","#
        + #""message":{"id":"\#(message)","model":"claude-opus-5-5","usage":{"input_tokens":\#(input),"#
        + #""output_tokens":1}}}"# + "\n"
}

/// A temporary home with transcripts, an app root and a login shell that exports `configDir`; no `claude` installed.
final class Machine: Sendable {
    let home = FileManager.default.temporaryDirectory.appending(path: "home-\(UUID())", directoryHint: .isDirectory)
    let paths = AppPaths.temporary()
    let fileEvents = FakeFileEvents()
    let fileReader = FakeFileReader()
    let time = FakeTimeSource(now: try! Date("2026-09-28T12:00:00Z", strategy: .iso8601))

    deinit {
        try? FileManager.default.removeItem(at: home)
        try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent())
    }

    /// `path` relative to the home folder.
    func write(_ path: String, _ text: String, append: Bool = false) throws {
        let url = home.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard append, let handle = try? FileHandle(forWritingTo: url) else { return try Data(text.utf8).write(to: url) }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    func activity(configDir: String = "") -> any ActivitySource {
        let shell = FakeProcessRunner { request in
            guard request.executable.path == "/bin/zsh" else { throw CocoaError(.fileNoSuchFile) }
            return ProcessResult(exitCode: 0, stdout: "profile noise\n\(configDir)\n", stderr: "")
        }
        return ClaudeCodeProvider(
            runner: shell, fileEvents: fileEvents, fileReader: fileReader, paths: paths, home: home,
            shell: URL(filePath: "/bin/zsh"), time: time, calendar: utc
        ).activity!
    }
}

/// The next report, or `nil` after `timeout`.
func next(_ reports: AsyncStream<ActivityReport>, within timeout: Duration = .seconds(2)) async -> ActivityReport? {
    await withTaskGroup(of: ActivityReport?.self) { group in
        group.addTask { await reports.first { _ in true } }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        defer { group.cancelAll() }
        return await group.next() ?? nil
    }
}

/// US-5, FR-22, FR-24, FR-28: every root, de-duplicated across files, the probe folder's project left out.
@Test func reportsTheDaysOfAllRoots() async throws {
    let machine = Machine()
    try machine.write(".claude/projects/-work/s1.jsonl", entry("m1") + entry("m1") + entry("m2", session: "s2"))
    // A resumed session repeats earlier entries in a new file.
    try machine.write(".claude/projects/-work/s3.jsonl", entry("m1"))
    try machine.write("custom/projects/-other/s4.jsonl", entry("m3", at: "2026-09-27T23:59:59Z"))
    let probe = machine.paths.providerFolder(.claudeCode).appending(path: "probe").path(percentEncoded: false)
    try machine.write(".claude/projects/\(probe.replacing(/[^a-zA-Z0-9]/, with: "-"))/p.jsonl", entry("m4"))

    let reports = machine.activity(configDir: machine.home.appending(path: "custom").path).reports()
    let report = try #require(await next(reports))

    #expect(report.provider == .claudeCode)
    #expect(report.days.map(\.day.rawValue) == ["2026-09-27", "2026-09-28"])
    let today = try #require(report.days.last)
    #expect(today.requests == 2)
    #expect(today.sessions == 2)
    #expect(today.tokens == TokenCounts(input: 20, output: 2))
    #expect(today.byModel == ["claude-opus-5-5": TokenCounts(input: 20, output: 2)])
}

/// FR-23, FR-26, SPEC §8.3.5: a change brings appended lines, a replaced file counts anew, a deleted one drops out,
/// and lines that fail to decode are counted.
/// SPEC §16.4: the roots, the transcripts and the history are all read through `FileReading`, so the conformance suite
/// sees every read.
@Test func readsThroughTheFileReader() async throws {
    let machine = Machine()
    try machine.write(".claude/projects/-work/s1.jsonl", entry("m1"))

    _ = try #require(await next(machine.activity().reports()))

    let reads = Set(machine.fileReader.reads.map(\.standardizedFileURL.path))
    let home = machine.home.standardizedFileURL.path
    #expect(reads.contains("\(home)/.claude/projects"))
    #expect(reads.contains("\(home)/.config/claude/projects"))
    #expect(reads.contains("\(home)/.claude/projects/-work/s1.jsonl"))
    #expect(reads.contains(machine.paths.providerFolder(.claudeCode).appending(path: "history.json").path))
}

@Test func followsChanges() async throws {
    let machine = Machine()
    try machine.write(".claude/projects/-work/s1.jsonl", entry("m1") + "not json\n")
    try machine.write(".claude/projects/-work/s2.jsonl", entry("m2"))
    let reports = machine.activity().reports()
    #expect(await next(reports)?.skippedLines == 1)

    try machine.write(".claude/projects/-work/s1.jsonl", entry("m3"), append: true)
    machine.fileEvents.send([])
    #expect(await next(reports)?.days.last?.requests == 3)

    try machine.write(".claude/projects/-work/s1.jsonl", entry("m4", input: 5))
    try FileManager.default.removeItem(at: machine.home.appending(path: ".claude/projects/-work/s2.jsonl"))
    machine.fileEvents.send([])
    let report = try #require(await next(reports))
    #expect(report.days.last?.tokens == TokenCounts(input: 5, output: 1))
    #expect(report.skippedLines == 0)
}

/// FR-24: when duplicates disagree, the first line in path order counts, also after an append to that file; lines
/// without a key count each.
@Test func firstDuplicateInPathOrderCounts() async throws {
    let machine = Machine()
    try machine.write(".claude/projects/-work/b.jsonl", entry("m1", input: 2) + entry("m1", input: 3))
    try machine.write(".claude/projects/-work/a.jsonl", entry("m1", input: 1))
    let unkeyed =
        #"{"type":"assistant","timestamp":"2026-09-28T10:00:00.000Z","#
        + #""message":{"model":"claude-opus-5-5","usage":{"input_tokens":100}}}"# + "\n"
    try machine.write(".claude/projects/-work/c.jsonl", unkeyed + unkeyed)
    let reports = machine.activity().reports()
    let first = try #require(await next(reports)?.days.last)
    #expect(first.requests == 3 && first.tokens.input == 201)

    try machine.write(".claude/projects/-work/a.jsonl", entry("m1", input: 4), append: true)
    machine.fileEvents.send([])
    let appended = try #require(await next(reports)?.days.last)
    #expect(appended.requests == 3 && appended.tokens.input == 201)
}

/// SPEC §12: a rescan (popover opened, wake) reports on the open streams without a file event.
@Test func rescanReportsOnOpenStreams() async throws {
    let machine = Machine()
    let activity = machine.activity()
    let reports = activity.reports()
    #expect(await next(reports)?.days == [])

    try machine.write(".claude/projects/-work/s1.jsonl", entry("m1"))
    await activity.rescan()
    #expect(await next(reports)?.days.count == 1)
}

/// FR-29: a day more than 48 h ago is frozen, so deleting its transcript keeps it.
@Test func frozenDaysSurviveDeletedTranscripts() async throws {
    let machine = Machine()
    try machine.write(".claude/projects/-work/old.jsonl", entry("m1", at: "2026-09-25T10:00:00Z"))
    try machine.write(".claude/projects/-work/new.jsonl", entry("m2"))
    let reports = machine.activity().reports()
    #expect(await next(reports)?.days.map(\.day.rawValue) == ["2026-09-25", "2026-09-28"])

    try FileManager.default.removeItem(at: machine.home.appending(path: ".claude/projects/-work"))
    machine.fileEvents.send([])
    #expect(await next(reports)?.days.map(\.day.rawValue) == ["2026-09-25"])
}
