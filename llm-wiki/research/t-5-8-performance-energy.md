---
type: research
status: answered
updated: 2026-10-03
tracks: [Packages/ContribusageKit/Sources/ContribusageCore/Scheduling/RefreshCoordinator.swift, Packages/ContribusageKit/Sources/ContribusageCore/Scheduling/Schedule.swift, App/AppState.swift, App/Popover/PopoverView.swift]
tags: [research, performance, energy]
---
# T-5.8: idle CPU, memory, latency and energy

- **Spec:** NFR-1 to NFR-4, NFR-14, T-5.8 · **Blocks:** T-5.8 · **Answered:** 2026-10-03

## Question
Does the Release build meet NFR-1 to NFR-4 and NFR-14 with one provider and real transcripts?

## Method
- Release build of e942a41 (`xcodebuild … -configuration Release`, `lipo` prints `arm64`), launched from `.build/xcode`, Claude Code provider enabled, a real transcript tree of <n> files. Apple M3 as the stand-in for an M1, as in [[decisions/0026-nfr-7-on-an-m3]].
- NFR-1: popover closed, `ps -o time=` every 10 s for 10 min; a nonzero count of child processes would mark a `claude` probe (a refresh, outside NFR-1's scope). A second window kept every Claude Code session on the Mac quiet, because each transcript write wakes the activity source.
- NFR-2: `footprint <pid>` at the start and end of the 10 minutes.
- NFR-14: `top -l 2 -s 60 -stats cpu,idlew,power` over one minute, and the scheduling code.
- NFR-3 and NFR-4: code review only; Instruments and the Thread Performance Checker were not run.

## Findings
| Check | Result | Budget |
|---|---|---|
| CPU, popover closed, no transcript writes (7.7 min) | 0.31 s, 0.07 % | below 0.1 % |
| CPU, popover closed, a Claude Code session writing transcripts (10 min) | 1.20 s, 0.2 % | — (activity updates, not idle) |
| Footprint | 43 → 47 MB | below 80 MB |
| Idle wakeups, energy impact (1 min) | 3, 0.1 | — |

- While idle, CPU rises in steps of 0.01 to 0.07 s once a minute: the popover's `TimelineView(.periodic(by: 60))` ticks with the popover closed. NFR-1 allows one timer per minute.
- Each burst of transcript writes costs the activity source about 0.1 to 0.4 s of CPU, because an incremental pass opens every transcript ([[research/nfr-7-transcript-scan]]). That is work caused by a running Claude Code session, not idle cost. If it becomes a problem, the fix is to read only the files named in the file events.
- NFR-14: `RefreshCoordinator` has one sleep loop with 10 % tolerance; the shortest automatic interval is 5 min (Claude Code limits), then 10 min (GitHub); `Schedule.nextRun` returns `nil` while the Mac sleeps and doubles intervals in Low Power Mode (`ScheduleTests`).
- NFR-3: opening the popover only starts `coordinator.popoverOpened()` in a detached `Task`; the view renders the state already in memory.
- NFR-4: probe, file reads and parsing run in the core's actors and `Task(priority: .utility)`; the app target keeps views and wiring.

## Outcome
- T-5.8 ticked in SPEC §17.5. No spec change: the measured values fit NFR-1, NFR-2 and NFR-14.
- Open: NFR-3 and NFR-4 still lack an Instruments run, and an M1 run is still missing.
- Measured before T-5.13: since then an activity source nobody uses (section hidden, layer out of the heatmap) is not watched, and GitHub skips passes while nothing uses it, so the idle figures are an upper bound.
