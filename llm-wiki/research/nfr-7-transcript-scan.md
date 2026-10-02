---
type: research
status: answered
updated: 2026-10-02
tracks: [Packages/ContribusageKit/Tests/ContribusageClaudeCodeTests/TranscriptActivityPerformanceTests.swift, Packages/ContribusageKit/Tests/ContribusageClaudeCodeTests/TranscriptTree.swift]
tags: [research, performance, activity]
---
# NFR-7: scanning 500 MB of transcripts

- **Spec:** NFR-7, NFR-2, T-4.7 · **Blocks:** ADR-024's verdict · **Answered:** 2026-10-02

## Question
How long do the launch scan and an incremental update of a 500 MB transcript tree take, and what does the live index cost in memory?

## Method
- `TranscriptTree` (test target) writes a seeded tree under a temporary folder: sessions under `projects/<encoded project>/` plus `subagents/agent-*.jsonl`, user tool-result lines of 200 B to 4 KB (a few up to 30 KB), one to four assistant lines per response repeating its usage (SPEC §8.3.3), timestamps over 30 days. 520 MB: 273 files, 196,788 lines, 140,607 of them with usage, 56,181 requests.
- `TranscriptActivityPerformanceTests` (opt-in, `CONTRIBUSAGE_PERF_TESTS=1`) drives `TranscriptActivity` through the fake process runner and `FakeFileEvents`: first scan = time to the first report, with the freshly generated files in the page cache (a truly cold read after boot needs `sudo purge` and is not measured); utility QoS comes from `TranscriptActivity`'s own `Task(priority: .utility)`, not from the test; incremental = one appended usage line, then one file event, time to the report that shows it. Memory is the process's `phys_footprint` from `task_info`.
- Release: `CONTRIBUSAGE_PERF_TESTS=1 swift test -c release --package-path Packages/ContribusageKit -Xswiftc -warnings-as-errors -Xswiftc -enable-testing --filter scansFiveHundred` (`-enable-testing` because the target's other files use `@testable`). Debug: without `-c release` and `-enable-testing`. Apple M3, judged by [[decisions/0026-nfr-7-on-an-m3]].

## Findings
Before the fix (6eb98f1):

| Build | First scan | Incremental | Footprint before → after scan → after update |
|---|---|---|---|
| Release (3 runs) | 3.1–3.9 s | 63–93 ms | ~95 → 540–640 → ~480 MB |
| Debug | 5.8–6.1 s | 114–121 ms | ~95 → 590 → 481 MB |

After the fix (d78b912, and again after the `FileReading` seam in 19d83e7; release runs agree within 15 %):

| Build | First scan | Incremental | Footprint before → after scan → after update, peak |
|---|---|---|---|
| Release | 1.48–1.67 s | 41–45 ms | 9 → 36 → 36 MB, peak 36 MB |
| Debug | 1.65 s | 63 ms | 9 → 36 → 36 MB |

- Time: inside NFR-7 with a wide margin, also under the half budget of ADR-026. A `sample` of the release scan before the fix put about 60 % of busy time in splitting the read bytes into lines (`Data.split`), 15–20 % in `JSONDecoder`, about 5 % in `read`.
- Memory before the fix: the scan left the footprint about 390 MB higher, against NFR-2's 80 MB for the whole app. Measured per stage with `phys_footprint`, `malloc_zone_statistics` and `vmmap --summary`, it had four causes:
  1. `FileHandle.readToEnd()` returns autoreleased data and the whole scan is one actor job, so no transcript was freed before the scan ended (518 MB in use right after it). The freed file-sized blocks then stayed dirty in malloc's large cache (about 290 MB in 165 "Malloc Large (empty)" regions); `malloc_zone_pressure_relief` returned nothing.
  2. The live index kept all 140,607 usage lines, repeats included, each with its own heap strings: 57 MB.
  3. Concatenating each file's bytes and copying every line into its own `Data` left about 90 MB more in that cache.
  4. The generator's freed buffers inflated the "before" value by 20 to 100 MB, so growth was unreliable.
- The fix: the reader streams each file through a 64 KB buffer and hands lines to a closure ([[modules/core]]); the live index keeps the first line per key ([[modules/claude-code]]); the generator writes in 64 KB pieces. Growth is now 27 MB for 520 MB of transcripts, and the opt-in test asserts at most 40 MB after the scan and after an update (25 MB app baseline at the M1 check + 40 MB stays under NFR-2's 80 MB). Next step if it must shrink: a compact per-key value instead of `TranscriptLine`.
- The generated files average 1.9 MB; a real tree with many more small files weighs more on the incremental path, which opens every transcript per pass.

## Outcome
- [[decisions/0024-live-index-in-memory]]: the live index stays in memory; `live-index.json` removed from SPEC §10.7.
- The live index follows SPEC §8.3.4 (unique keys only), and the perf test guards NFR-2 for the activity source.
