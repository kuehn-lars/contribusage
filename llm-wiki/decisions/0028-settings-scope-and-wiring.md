---
type: decision
status: accepted
updated: 2026-10-03
aliases: [ADR-028]
tags: [settings, scheduling, providers, app]
tracks: [App/Settings, App/AppState.swift, Packages/ContribusageKit/Sources/ContribusageCore/Scheduling/RefreshCoordinator.swift, Packages/ContribusageKit/Sources/ContribusageClaudeCode/ClaudeCodeProvider.swift]
---
# ADR-028: The Settings window's scope in T-5.2 and how its settings reach the coordinator

- **Decided:** 2026-10-02 · **Spec:** SPEC FR-2, FR-3, FR-33, US-7, US-12, §10.7, §11.6, T-5.2, T-5.10 · **Supersedes:** —

## Context
SPEC §11.6 lists controls that other tasks own: launch at login (T-5.3), copy diagnostics (T-5.5), the menu bar label (T-5.10) and the status line bridge (T-6.2). The interval settings must change a running schedule, "reset caches" must not fight the coordinator, which rewrites `state.json` from memory, and FR-2 forbids a disabled provider any process, while the Providers tab shows availability for every provider.

## Options
| Option | For | Against |
|---|---|---|
| T-5.2 builds every §11.6 control, inert ones included | One task completes the window | Controls without behaviour ship, and the menu bar mode type is designed before its renderer |
| T-5.2 builds the controls no other task owns | Every control works when it appears | The window grows with T-5.3 (done: General's launch at login toggle), T-5.5, T-5.10 and T-6.2 |

## Decision
T-5.2 builds the controls no other task owns; the menu bar display mode and menu bar provider settings move to T-5.10, next to the label that reads them. Intervals are settings a `Job` reads before every scheduling decision (`interval`, `limitsInterval(ProviderID)` for providers) as the policy's default, which `Schedule` clamps to the policy's bounds; `intervalsChanged()` reschedules at once. `resetCaches()` lives in the coordinator: it forgets every snapshot, keeps the notification keys and runs every source. Detecting availability and locating `claude` while the Providers tab is shown are allowed for a disabled provider: the user asked by opening the tab, and the registry's once-a-minute rule (FR-3) still bounds it.

## Consequences
- An edited `UserDefaults` value outside 5 to 60 min (or 10 min to 6 h) cannot break the schedule; it is clamped like any other interval.
- Keeping the notification keys means a reset cannot repeat a notification (FR-15); a cache reset is not a way to re-send one.
- "Delete data for this provider" is offered only while the provider is off, so no running activity source writes `history.json` back during or after the deletion.
- Enabling a provider calls `start()` again; `restore()` therefore publishes only for sources that show no state yet, or a rejected GitHub token would turn back into its snapshot and poll once more.
- A probe running when its provider is turned off still finishes (at most 30 s); its result lands in a group that is no longer shown.
