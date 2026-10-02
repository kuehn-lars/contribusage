---
type: research
status: open
updated: 2026-10-02
tracks: [Packages/ContribusageKit/Tests/ContribusageClaudeCodeTests/TranscriptActivityPerformanceTests.swift, Packages/ContribusageKit/Tests/ContribusageClaudeCodeTests/TranscriptTree.swift]
tags: [research, performance, activity]
---
# NFR-7: scanning 500 MB of transcripts

- **Spec:** _NFR-7, NFR-2, T-4.7_ · **Blocks:** _ADR-024's verdict_ · **Answered:** _open (memory)_

## Question
How long do the launch scan and an incremental update of a 500 MB transcript tree take, and what does the live index cost in memory?

## Method
- `TranscriptTree` (test target) writes a seeded tree under a temporary folder: sessions under `projects/<encoded project>/` plus `subagents/agent-*.jsonl`, user tool-result lines of 200 B to 4 KB (a few up to 30 KB), one to four assistant lines per response repeating its usage (SPEC §8.3.3), timestamps over 30 days. 520 MB: 273 files, 196,788 lines, 140,607 of them with usage, 56,181 requests.
- `TranscriptActivityPerformanceTests` (opt-in, `CONTRIBUSAGE_PERF_TESTS=1`) drives `TranscriptActivity` through the fake process runner and `FakeFileEvents`: cold scan = time to the first report; incremental = one appended usage line, then one file event, time to the report that shows it. Memory is the process's `phys_footprint` from `task_info`.
- Release: `CONTRIBUSAGE_PERF_TESTS=1 swift test -c release --package-path Packages/ContribusageKit -Xswiftc -warnings-as-errors -Xswiftc -enable-testing --filter scansFiveHundred` (`-enable-testing` because the target's other files use `@testable`). Debug: without `-c release` and `-enable-testing`. Apple M3, judged by [[decisions/0026-nfr-7-on-an-m3]].

## Findings
| Build | Cold scan | Incremental | Footprint before → after scan → after update |
|---|---|---|---|
| Release (3 runs) | 3.1–3.9 s | 63–93 ms | ~95 → 540–640 → ~480 MB |
| Debug | 5.8–6.1 s | 114–121 ms | ~95 → 590 → 481 MB |

- Time: inside NFR-7 with a wide margin, also under the half budget of ADR-026. A `sample` of the release scan put about 60 % of busy time in splitting the read bytes into lines (`Data.split`), 15–20 % in `JSONDecoder`, about 5 % in `read`.
- Memory: the scan leaves the footprint about 390 MB higher, against NFR-2's 80 MB for the whole app.
- The generated files average 1.9 MB; a real tree with many more small files weighs more on the incremental path, which opens every transcript per pass.

## Outcome
- [[decisions/0024-live-index-in-memory]]: the live index stays in memory; `live-index.json` removed from SPEC §10.7.
