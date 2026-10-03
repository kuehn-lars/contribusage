---
type: decision
status: accepted
updated: 2026-10-04
aliases: [ADR-027]
tags: [notifications, scheduling, persistence]
tracks: [Packages/ContribusageKit/Sources/ContribusageCore/Notifications/NotificationPlanner.swift, Packages/ContribusageKit/Sources/ContribusageCore/Scheduling/RefreshCoordinator.swift]
---
# ADR-027: Notifications are planned in the coordinator from the persisted keys alone

- **Decided:** 2026-10-02 · **Spec:** SPEC FR-13 to FR-15, US-3, §9.2, §10.7, T-5.1 · **Supersedes:** —

## Context
SPEC §9.2 described `NotificationPlanner` as taking old and new limits plus the persisted keys. The keys (FR-15) live in `state.json`, which the `RefreshCoordinator` writes, and the app target may hold no logic. Something has to run the planner after each fetch, persist the keys before delivery, and tell a reset (FR-14) from a new reading.

## Options
| Option | For | Against |
|---|---|---|
| Plan in the app on each limits update | Coordinator unchanged | Logic and a second writer of `state.json` in the app target |
| Plan in the coordinator, compare old and new reports | Matches the old §9.2 wording | The previous report is gone after a restart, so a reset during downtime goes unseen |
| Plan in the coordinator from the persisted cycles alone | Survives restarts; one writer of `state.json` | A provider whose reset time jitters between readings would re-arm early |

## Decision
The limits job's `fetch` runs the planner after every fetch, so a restored snapshot is never planned. FR-15's keys are stored as one `Cycle` per provider and window label (`resetsAt`, the highest threshold sent, when it was sent), which `state.json` keeps under the optional field `notificationKeys` as `{"<provider id>": {"<label>": cycle}}`, so schema 2 stays. A cycle with another `resetsAt` than the window has ended: it is dropped, which re-arms the thresholds, and with `notifyOnReset` one reset note follows. The app supplies the settings, read before every plan, and the delivery (`RefreshCoordinator.Notifications`).

## Consequences
- Every note of one window and cycle shares one identifier, so a jump over 80 and 95 sends both (one per threshold, US-3) and Notification Center keeps the 95 % one; the reset note replaces the cycle's last warning.
- The highest threshold stands for every lower one, so a threshold added below it mid-cycle waits for the next cycle; at 96 % a warning "at 90 %" would be late anyway. FR-15 says so.
- A window past its `resetsAt` is skipped until the next fetch (FR-11), so a stale reading cannot warn.
- Pushed limits (the status line bridge, T-6.2) are not planned yet; that task routes them through the same `notify`.
- "Reset caches" keeps the keys, so the refetch after it cannot repeat a notification ([[decisions/0028-settings-scope-and-wiring]]).
- A run on wake or reconnect (T-5.6) plans its report like any fetch; the keys keep it from repeating a note.
- Titles are looked up in the core's String Catalog; the window inside them is the provider's window title, while the cycle stays keyed by the label ([[decisions/0031-string-catalogs]], [[decisions/0033-provider-tool-texts]]).
- Revisit if a provider's reset time is not stable within a cycle.
- FR-46 (T-5.13): because notifications are planned from fetched limits, a provider's limits keep running while it is on, even with its limits section hidden.

Pushed reports are planned like fetched ones; restored snapshots still never are ([[decisions/0036-pushed-limits-and-debug-fake-provider]]).
