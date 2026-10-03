---
type: decision
status: accepted
updated: 2026-10-03
aliases: [ADR-022]
tags: [core, github, scheduling]
tracks: [Packages/ContribusageKit/Sources/ContribusageCore/Scheduling/RefreshCoordinator.swift, App/AppState.swift]
---
# ADR-022: GitHub joins the coordinator as a typed job

- **Decided:** 2026-09-30 · **Spec:** SPEC §8.4.3, §8.4.4, §10.7, §12, §13, T-3.6, R-4 · **Supersedes:** —

## Context
[[decisions/0018-refresh-coordinator-shape#Decision]] lets GitHub join the coordinator's passes as a job the app supplies, persisted under its own key in `state.json`. The core cannot name `GitHubReport` (NFR-17), yet it must persist and restore it. SPEC §12's GitHub row left four points open: the manual floor, whether Retry may run after a 401 ("no automatic retries", §8.4.3), whether "wait until reset" lets Retry or the popover run earlier, and T-3.6 waited on R-4 for the calendar's time zone.

## Options
| Option | For | Against |
|---|---|---|
| Coordinator generic over GitHub's value type | Typed snapshots, persisted and restored like the limits; one loop | The app names `RefreshCoordinator<GitHubReport>`, provider tests `<Int>` |
| Type-erased job storing encoded `Data` | Coordinator stays non-generic | Base64 inside `state.json`, decoding in the app |
| Own scheduler in `ContribusageGitHub` | Core untouched | Repeats the loop, conditions, manual and popover handling; contradicts ADR-018 |

## Decision
`RefreshCoordinator<GitHubValue>` runs one kind of thing, a `Job<Value>`: policy, origin, fetch, `onUpdate`, and the extra trigger dates a value brings. Each enabled provider's limits become a `Job<LimitsReport>` (origin `.poll`, a window's reset as trigger); GitHub is the optional `Job<GitHubValue>` the app supplies (`GitHubReport.policy`, manual floor 30 s, origin `.github`). One `run` handles offline, due and refresh for both, over a `Record` class that stays inside the actor. GitHub runs after the providers; its snapshot sits under `github` in `state.json` (optional, so schema 1 still reads). The rules live in the shared `nextRun` and apply to any job in these states:
- No token or `failed(.unauthorized)`: no automatic run, and being offline does not replace the state; a manual refresh (Retry) still runs, since §8.4.3 forbids only automatic retries. A missing token is thrown as `SourceError.tokenMissing` and mapped to `notConfigured(.githubTokenMissing)`, as `toolNotFound` is to `toolNotInstalled`.
- Whether GitHub runs at all follows FR-43 and FR-46: `AppState` sends `Demand.github` to `setGitHubWanted(_:)` (T-5.13, T-5.14).
- `failed(.rateLimited(until:))`: the next run is the reset, as §13's "retrying at 15:04" promises; manual refresh and the popover cannot pull it earlier.
- A token change (`gitHubTokenChanged()`) replaces GitHub's record and writes `state.json` without it, so the old account's data goes; a fetch still running with the old token finishes into the replaced record, which nothing reads. `AppState.connectGitHub(token:)` and `disconnectGitHub()` own the account and call it, so no caller can save a token without it.

The app passes `Calendar.current` to `GitHubAccount.report(now:calendar:)`, the default [[decisions/0021-stats-calendar-parameter]] named; R-4 no longer blocks T-3.6.

## Consequences
- A GitHub menu bar mode (T-5.10) keeps GitHub wanted through `Demand.github` (FR-46), whatever the popover shows.
- R-4 changes one argument in `AppState.live`, not the coordinator.
- `GitHubReport.staleAfter` became `GitHubReport.policy.staleAfter`.
- `ContributionCalendar` keeps GitHub's `weeks` (SPEC §10.5), so the heatmap's columns are `weeks.suffix(26)` with no weekday arithmetic; `days` is derived.
- Notification keys joined `state.json` the same way in T-5.1, as the optional field `notificationKeys` ([[decisions/0027-notification-planning-in-the-coordinator]]). The coordinator reads `state.json` through `JSONStore.read(_:using: LiveFileReader())`; the reader is explicit since T-4.7 ([[decisions/0025-read-roots-check-with-t-4-7]]).
- The GitHub job's `interval` reads the `githubInterval` setting before every decision ([[decisions/0028-settings-scope-and-wiring]]).
- Offline replaces neither a waiting token nor a rate limit (`Record.outlastsOffline`, T-5.6): reconnecting before the reset still waits for it.
- T-5.13 (FR-46): `setGitHubWanted(_:)` takes the app's `Demand.github`; while false, passes skip the GitHub job, and wanting it again runs what is due at once.
- T-5.14 (FR-43): the GitHub switch removes GitHub from the sources that are on, so `Demand.github` turns false and the job is skipped; the token stays in the Keychain.
- Revisit if a second non-provider source appears: then a list of jobs instead of one generic slot; `run` already takes any job.
- GitHub's heatmap layer reads the job's last snapshot, stale or failed ones dimmed (T-5.16, SPEC §11.4).
