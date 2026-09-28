---
type: module
status: active
updated: 2026-09-28
tracks: [Packages/ContribusageKit/Sources/ContribusageCore, Packages/ContribusageKit/Tests/ContribusageCoreTests, Packages/ContribusageKit/Package.swift]
tags: [core, architecture]
---
# ContribusageCore

The provider-neutral heart of the package: models, provider protocols and registry, the refresh scheduler, notification planning, generic activity infrastructure, persistence and the support seams (time, processes, HTTP, Keychain, file events, paths). It knows no concrete provider and nothing about GitHub (NFR-17).

## Spec
- **Sections:** SPEC §7 (provider model), §9 (architecture), §10.1 to §10.4, §10.6, §10.7 (types, seams, persistence), §12 (refresh policy), §13 (error handling)
- **Requirements:** FR-1 to FR-5, FR-10, FR-13 to FR-15, FR-26, FR-29; NFR-4, NFR-5, NFR-14, NFR-17, NFR-18
- **Tasks:** T-1.4 to T-1.6, T-2.4, T-2.6, T-3.1 (Keychain `SecretStore`), T-4.3, T-4.4, T-5.1 (planner), T-5.6
- **Path:** `Packages/ContribusageKit/Sources/ContribusageCore/`

## Depends on
Nothing inside the package. Every other target depends on it.

## Contract
Built so far: `ProviderID` (SPEC §10.2), encoded as its bare raw value. `ArchitectureTests` enforces NFR-17 on every `swift test` run: the core imports no other package target, every other target imports only the core ([[decisions/0014-build-and-ci-foundation]]).

## Things that bite
Open design points in SPEC §9 and §10, to settle in the task named (none is decided yet):
- **The coordinator cannot see GitHub.** SPEC §9.1 draws `RefreshCoordinator → GitHubService`, but NFR-17 forbids the core importing GitHub. The coordinator needs a neutral seam for polled work (a `SchedulePolicy` plus an async refresh), which the app fills with GitHub. Decide in T-2.6, before T-3.6.
- **`ActivitySource` is shallow.** `start`, `stop`, `rescan` and `reports()` carry ordering rules a caller must learn. A stream whose termination stops the watching (cancel the consuming task) would leave `reports()` and `rescan()`, and turns "`stop()` releases file watching" (SPEC §16.4) into a property of cancellation. Decide in T-1.6.
- **`AppPaths` has one adapter.** Live and fake differ only in the root folder, so a struct holding the root may replace the protocol; tests pass a temporary folder. Decide in T-1.4.
- **`ProviderRegistry` may be a pass-through.** Order is the array from `ProviderRegistration`, enablement a set in `UserDefaults`, availability the coordinator's state. Apply the deletion test in T-1.6: keep it only if the registry's tests hold behaviour the coordinator would otherwise repeat.

## Related
[[decisions/0004-logic-in-contribusagekit-package]] · [[decisions/0005-json-file-persistence]] · [[decisions/0010-provider-abstraction-from-day-one]] · [[modules/test-support]]
