---
type: decision
status: accepted
updated: 2026-10-04
aliases: [ADR-036]
tags: [core, scheduling, app, providers]
tracks: [Packages/ContribusageKit/Sources/ContribusageCore/Scheduling/RefreshCoordinator.swift, App/DebugFakeProvider.swift, App/ProviderRegistration.swift]
---
# ADR-036: Pushed limits in the coordinator, the debug fake provider in the app

- **Decided:** 2026-10-04 · **Spec:** SPEC §10.1, §12 rule 9, §15.5, US-11 · **Supersedes:** —

## Context
T-5.12 checks US-11 by hand: a Debug build with `CONTRIBUSAGE_FAKE_PROVIDER` registers a second provider whose limits are only pushed. Two gaps stood in the way. `RefreshCoordinator` ran only polled sources ([[decisions/0018-refresh-coordinator-shape]]) and never read `LimitsSource.pushedUpdates()`, so a push-only provider's limits stayed "loading". And SPEC §15.5 named a `DebugFakeProvider` that existed nowhere: `FakeProvider` lives in `ContribusageTestSupport`, which imports `Testing` and is no product, so the app cannot link it.

## Options
| Option | For | Against |
|---|---|---|
| Coordinator consumes pushes | US-11's push-only shape works end to end; the status line bridge (T-6.2) needs it anyway | A second way into a record besides `refresh` |
| The debug fake polls | No core change | Does not exercise push-only; leaves the gap for T-6.2 |
| Debug provider as an app file under the flag | One file, never compiled without the flag | Provider code outside a provider target, debug only |
| Debug provider as a package target | Fits "provider code in its target" | A product the app links in every configuration, or per-configuration linking |

## Decision
The coordinator keeps one task per enabled provider with limits that consumes `pushedUpdates()`; each report is a success with origin `push`: persisted, planned for notifications and shown. `start()` starts the missing consumers and cancels those of disabled providers, so the app calls it on every enable and disable (US-12). `restore()` shows a cached snapshot for every provider with limits, polled or not. `DebugFakeProvider` is `App/DebugFakeProvider.swift` inside `#if CONTRIBUSAGE_FAKE_PROVIDER`: one weekly window at 85 % (past the default thresholds), pushed only, and activity on every other day of the last 26 weeks so its heatmap layer shows.

## Consequences
A push also moves a polled source's last success, so a bridge push postpones the next probe; T-6.2 decides whether that is wanted. A push resets no backoff count. The flag is set on the command line (SPEC §15.5), not in a configuration, so no shipped build can carry the fake.
