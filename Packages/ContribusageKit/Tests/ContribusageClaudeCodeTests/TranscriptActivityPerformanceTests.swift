import ContribusageClaudeCode
import ContribusageCore
import ContribusageTestSupport
import Foundation
import Testing

/// The generator behind the NFR-7 test, kept honest at a tiny size: the activity source counts what it wrote.
@Test func generatedTreeCountsAsWritten() async throws {
    let machine = Machine()
    let projects = machine.home.appending(path: ".claude/projects", directoryHint: .isDirectory)
    let tree = try TranscriptTree.generate(in: projects, bytes: 300_000, end: machine.time.now)

    let files = TranscriptFiles.files(
        in: [projects], excludingProjectOf: machine.paths.root, fileReader: LiveFileReader())
    #expect(files.count == tree.files)
    #expect(files.contains { $0.path.contains("/subagents/") })
    #expect(tree.bytes >= 300_000)
    // SPEC §8.3.3: a response is written as several lines that repeat its usage.
    #expect(tree.usageLines > tree.requests)
    #expect(tree.lines > tree.usageLines)

    let reports = machine.activity().reports()
    let report = try #require(await next(reports))
    #expect(report.skippedLines == 0)
    #expect(report.days.count > 10)
    #expect(report.days.reduce(0) { $0 + $1.requests } == tree.requests)
    #expect(report.days.reduce(into: TokenCounts()) { $0 += $1.tokens } == tree.tokens)
}

/// NFR-7 on 500 MB of transcripts: only with `CONTRIBUSAGE_PERF_TESTS=1`, ideally with `-c release`. The cold scan is
/// the time to the first report, the incremental update the time from a file event to the report with one more line.
/// NFR-2: the activity source adds at most 40 MB to the footprint, so the app (baseline under 25 MB, M1 check) stays
/// under 80 MB with one provider.
@Test(.enabled(if: ProcessInfo.processInfo.environment["CONTRIBUSAGE_PERF_TESTS"] == "1"))
func scansFiveHundredMegabytesWithinNFR7() async throws {
    let machine = Machine()
    let projects = machine.home.appending(path: ".claude/projects", directoryHint: .isDirectory)
    let tree = try TranscriptTree.generate(in: projects, bytes: 500_000_000, end: machine.time.now)
    let file = try #require(
        TranscriptFiles.files(in: [projects], excludingProjectOf: machine.paths.root, fileReader: LiveFileReader())
            .first)
    let clock = ContinuousClock()
    let before = footprint()

    var start = clock.now
    let reports = machine.activity().reports()
    let cold = try #require(await next(reports, within: .seconds(300)))
    let scan = clock.now - start
    let afterScan = footprint()

    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(entry("msg_perf", request: "req_perf", at: "2026-09-28T11:00:00.000Z").utf8))
    try handle.close()
    start = clock.now
    machine.fileEvents.send([file])
    let updated = try #require(await next(reports, within: .seconds(60)))
    let incremental = clock.now - start
    let afterUpdate = footprint()

    print(
        "NFR-7: \(tree.bytes / 1_000_000) MB, \(tree.files) files, \(tree.lines) lines (\(tree.usageLines) usage,",
        "\(tree.requests) requests); cold scan \(scan), incremental \(incremental);",
        "footprint before \(before.now) MB, after scan \(afterScan.now) MB,",
        "after update \(afterUpdate.now) MB, peak \(afterUpdate.peak) MB",
        "(peak growth at most \(afterUpdate.peak - before.now) MB)")
    #expect(cold.days.reduce(0) { $0 + $1.requests } == tree.requests)
    #expect(updated.days.reduce(0) { $0 + $1.requests } == tree.requests + 1)
    #expect(scan < .seconds(30))
    #expect(incremental < .milliseconds(200))
    #expect(afterScan.now - before.now <= 40)
    #expect(afterUpdate.now - before.now <= 40)
}

/// The process's physical footprint and its peak so far, in MB.
private func footprint() -> (now: Int, peak: Int) {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return (-1, -1) }
    return (Int(info.phys_footprint) / 1_000_000, Int(info.ledger_phys_footprint_peak) / 1_000_000)
}
