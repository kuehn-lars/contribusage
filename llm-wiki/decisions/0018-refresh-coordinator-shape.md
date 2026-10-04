---
type: decision
status: accepted
updated: 2026-10-04
aliases: [ADR-018]
tags: [core, scheduling, persistence]
tracks: [Packages/ContribusageKit/Sources/ContribusageCore/Scheduling]
---
# ADR-018: `RefreshCoordinator` runs passes, the app feeds conditions

- **Decided:** 2026-09-29 · **Spec:** SPEC §9.2, §10.1, §10.2, §12, §13, T-2.6, T-2.7, T-3.6 · **Supersedes:** —

## Context
T-2.6 builds the scheduler of SPEC §12. Four points were open: how the neutral core learns whether a polled source needs the network (rule 2 says the provider declares it, but `ProviderDescriptor` had no field), which `Origin` a polled snapshot carries when the core cannot name a provider's constant, how wake, network and Low Power Mode reach a core actor that must stay testable without them, and how GitHub joins a coordinator that NFR-17 forbids from importing it ([[modules/core#Things that bite]]).

## Options
| Option | For | Against |
|---|---|---|
| `needsNetwork` in `SchedulePolicy` | Declared exactly where a polled source is described; the pure function sees it | Every policy literal names it |
| A separate descriptor flag | Policy stays timing only | `nextRun` would need a second input for one bit |
| Coordinator observes `NWPathMonitor`, `NSWorkspace`, `ProcessInfo` itself | Self-contained | Platform notifications in the core, untestable without a Mac that sleeps |
| App pushes `ScheduleConditions` through `update(_:)` | Pure core; tests set conditions directly | The app owns three observers |
| Timer per source | Independent schedules | Parallel fetches break registry order and NFR-18 by construction |
| One loop running serialized passes | NFR-18 and registry order hold by construction; `runDue()` is testable without waiting | One slow fetch delays the others (they would queue at the process gate anyway) |

## Decision
`SchedulePolicy` gains `needsNetwork`. The app feeds `ScheduleConditions` (online, Low Power Mode, asleep, last wake) through `update(_:)`. The coordinator runs passes: each waits for the previous one, walks the enabled providers in registry order and fetches every source `Schedule.nextRun` says is due; one loop sleeps until the earliest next date with 10 % tolerance (NFR-14) and restarts on every condition change or manual refresh. A fresh snapshot carries the core's `Origin.poll`, a restored one `Origin.cache`. The unsupported-plan recheck runs through `nextRun` as a 6 h policy, so sleep, offline and wake apply to it too. GitHub (T-3.6) joins the same passes as a neutral polled job the app supplies: a `SchedulePolicy` and an async fetch, persisted under its own key in `state.json`.

## Consequences
- The coordinator knows nothing it could only learn from the platform; the app wiring (T-2.7) is the untested seam, which the manual matrix (SPEC §16.5) covers.
- `state.json` holds `limits` keyed by provider ID today; GitHub snapshots and notification keys join as optional fields, so schema version 1 stays readable.
- Enabling a provider does not wake the loop; the app calls `start()` again.
- GitHub joined in T-3.6 with the coordinator generic over its value ([[decisions/0022-github-job-in-the-coordinator]]).
- The extra triggers of SPEC §12 (popover opened, a window's reset) joined the same passes in T-2.7 as `triggers` dates ([[decisions/0019-extra-refresh-triggers]]).
- T-5.1 plans notifications after each polled limits fetch in the same passes ([[decisions/0027-notification-planning-in-the-coordinator]]). Delivery is a synchronous hand-off to the app's queue, so the 3 s spacing of FR-52 never holds up a pass ([[decisions/0038-notification-cycles-and-delivery]]).
- T-5.2's settings enter the same actor as calls: `intervalsChanged()` reschedules, `resetCaches()` forgets the snapshots and runs a pass ([[decisions/0028-settings-scope-and-wiring]]).
- T-5.6: the wake is a trigger like the others, and `nextRun` treats a source shown offline as a manual refresh, so it runs on reconnect within its floor instead of showing "Offline" until its next interval.
- T-5.13: what runs follows use (FR-46); provider limits keep running while a provider is on, and GitHub skips passes while `setGitHubWanted(false)` ([[decisions/0022-github-job-in-the-coordinator]]).
- Revisit if a provider's fetch is slow enough that queueing behind it matters: then passes per provider, with the process gate as the only global lock.
- A provider's limits job hands the planner its whole descriptor, for the display name and the window title ([[decisions/0033-provider-tool-texts]]).

Since T-5.12 the coordinator also consumes pushed limits, beside the passes rather than in them ([[decisions/0036-pushed-limits-and-debug-fake-provider]]).
