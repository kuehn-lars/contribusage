import ContribusageCore
import ContribusageTestSupport
import Foundation
import Testing

@testable import ContribusageClaudeCode

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// One usage line in the shape of SPEC Appendix E.
func entry(
    _ message: String, request: String = "r", session: String = "s1", at stamp: String = "2026-09-28T10:00:00.000Z",
    input: Int = 10, model: String = "claude-opus-5-5"
) -> String {
    #"{"type":"assistant","sessionId":"\#(session)","timestamp":"\#(stamp)","requestId":"\#(request)","#
        + #""message":{"id":"\#(message)","model":"\#(model)","usage":{"input_tokens":\#(input),"#
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

    // Both sides alike, so `/var` against `/private/var` or a trailing slash cannot tell them apart.
    func resolved(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }
    let reads = Set(machine.fileReader.reads.map(resolved))
    let expected =
        [".claude/projects", ".config/claude/projects", ".claude/projects/-work/s1.jsonl"].map {
            machine.home.appending(path: $0)
        } + [machine.paths.providerFolder(.claudeCode).appending(path: "history.json")]
    for url in expected { #expect(reads.contains(resolved(url)), "not read: \(url.path)") }
}

/// NFR-2: lines read later share the session IDs and models the file already holds. Both are long enough to live
/// outside Swift's small-string storage, as real ones do.
@Test func appendedLinesShareTheFilesStrings() throws {
    let session = "8f14e45f-ceea-467a-a866-051f9ad3c5f1"
    let model = "claude-sonnet-4-5-20250929"
    func transcript(_ message: String) throws -> TranscriptActivity.Transcript {
        var transcript = TranscriptActivity.Transcript()
        let text = entry(message, session: session, model: model).dropLast()
        transcript.add(try #require(try TranscriptLine.decode(Data(text.utf8))))
        return transcript
    }
    func storage(_ text: String?) -> UInt? {
        text?.utf8.withContiguousStorageIfAvailable { UInt(bitPattern: $0.baseAddress) } ?? nil
    }
    var file = try transcript("m1")
    file.append(try transcript("m2"))

    let first = try #require(file.keyed["m1:r"])
    let later = try #require(file.keyed["m2:r"])
    #expect(storage(first.model) != nil && storage(first.sessionID) != nil)
    #expect(storage(later.model) == storage(first.model))
    #expect(storage(later.sessionID) == storage(first.sessionID))
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
