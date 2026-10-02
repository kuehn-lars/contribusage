---
type: decision
status: accepted
updated: 2026-10-02
aliases: [ADR-019]
tags: [core, scheduling, app]
tracks: [Packages/ContribusageKit/Sources/ContribusageCore/Scheduling]
---
# ADR-019: Extra refresh triggers are dates in `Schedule.nextRun`

- **Decided:** 2026-09-29 · **Spec:** SPEC §12 rules 7 and 8, FR-11, US-2, T-2.7 · **Supersedes:** —

## Context
SPEC §12 lists two extra triggers for polled limits: "popover opened and data older than 5 min" and "a window's reset time reached" (FR-11, "respecting the minimum interval"). T-2.6 left them to T-2.7 ([[decisions/0018-refresh-coordinator-shape]]). Both must keep NFR-5's budget, and the reset trigger must not turn a failing source into a probe every minimum interval.

## Options
| Option | For | Against |
|---|---|---|
| App runs a timer per window reset and calls the coordinator | Coordinator unchanged | A timer in the app while the popover is closed (NFR-1), untested wiring, duplicated schedule knowledge |
| Coordinator derives reset times from its own snapshots | Tested with a fake clock; the existing loop already sleeps until the earliest due date | The core reads `UsageWindow.resetsAt`, which it owns anyway |
| Trigger dates in `Schedule.nextRun` | One rule for both triggers, in the pure function; the minimum interval is the floor for both | One more parameter in the signature of rule 7 |
| A `manual`-style flag per trigger | Mirrors `manual` | Cannot express a future date (the reset) |

## Decision
`Schedule.nextRun` takes `triggers: [Date]`: the first one after the last run (success or attempt) runs a source at `max(trigger, lastRun + minimumInterval)` when that is sooner than its interval, skipping backoff. Filtering by the last run in the pure function means one attempt consumes a trigger. The coordinator passes its snapshot's `resetsAt` dates. `popoverOpened()` passes `now` as an argument to the one pass it starts, not as stored state, so data younger than the minimum interval is left alone rather than refreshed later.

## Consequences
- The app only reports the popover opening; it holds no timers of its own.
- After a failed attempt past a reset, the source returns to its backoff schedule.
- The same `resetsAt` changing between fetches is what re-arms notification thresholds ([[decisions/0027-notification-planning-in-the-coordinator]]).
- A window whose reported reset never moves forward (the tool keeps printing a past time) triggers nothing after the first attempt, since the trigger must lie after the last run.
