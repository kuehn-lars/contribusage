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
Built so far: `ProviderID` (SPEC §10.2), encoded as its bare raw value. The seams of SPEC §10.6 in `Support/`: the protocols `TimeSource`, `ProcessRunning` (with `ProcessRequest`, `ProcessResult`), `HTTPTransport`, `SecretStore` and `FileEvents`, and `AppPaths`, a struct whose `.live` root is `~/Library/Application Support/contribusage/` ([[decisions/0015-app-paths-struct]]). Live so far: `SystemTimeSource` and `URLSessionTransport` (ephemeral session; a non-HTTP response throws `URLError(.badServerResponse)`); the live process runner, Keychain store and FSEvents watcher come with T-2.4, T-3.1 and T-4.5. Persistence (SPEC §10.7) in `Persistence/JSONStore.swift`: a `PersistedFile` declares its `schemaVersion`; `JSONStore.write` stores it as the envelope `{"schemaVersion": n, "value": …}` (sorted keys) with an atomic write, creating missing folders `0700`. `JSONStore.read` returns `nil` for a missing file and throws `PersistenceError.unsupportedSchemaVersion` for any other version without touching the file: a cache ignores the error and is overwritten on its next write, `history.json` goes to its owner's backup and migration. `JSONStore.deleteProviderData` removes `providers/<id>/` (US-12); disk I/O stays here, `AppPaths` never touches the disk ([[decisions/0015-app-paths-struct]]). Dates use `JSONEncoder`'s default (seconds since 2001 as a double), which round-trips exactly. The provider framework (SPEC §10.2 to §10.4, T-1.6) in `Providers/`: `Provider.swift` holds `ProviderDescriptor`, `ProviderCapabilities`, `TokenCategory`, `SchedulePolicy`, `ProviderAvailability` and the protocols `UsageProvider`, `LimitsSource` and `ActivitySource`, whose watching runs while its `reports()` stream is consumed ([[decisions/0016-activity-source-stream-lifetime]]); `Reports.swift` the neutral outputs (`LimitsReport`, `UsageWindow`, `ActivityReport`, `ActivityDay`, `TokenCounts`, `DayKey`) and `SourceError`. `ProviderRegistry` is an actor: registration order is display order (FR-1, a duplicate ID traps), `enabledProviders()` applies the stored setting or, on first run, enables every provider that reports `available` (FR-2), and the caller persists the IDs it returns, and `availability(of:)` keeps `available` for the app's lifetime and re-detects anything else at most once per minute (FR-3). The registry earns its place through that caching and the first-run default, which the coordinator would otherwise repeat. `Models/Snapshot.swift` (SPEC §10.1, T-1.7): `Snapshot`, `Origin`, `SourceState`, `NotConfiguredReason`; `SourceState.snapshot` is the current or previous value the UI can show, `Snapshot.isStale(at:after:)` applies a policy's `staleAfter`. `Package.swift` gives a test target `resources: [.copy("Fixtures")]` with its first fixture (so far `ContribusageClaudeCodeTests`), read through `Bundle.module`. `ArchitectureTests` enforces NFR-17 on every `swift test` run: the core imports no other package target, every other target imports only the core ([[decisions/0014-build-and-ci-foundation]]).

## Things that bite
`createDirectory(attributes:)` sets `0700` only on folders it creates, never on existing ones; every writer under the root must create owner-only folders itself, which is why the bridge script (SPEC Appendix D) runs `mkdir` under `umask 077`.

`URL.path()` percent-encodes, so `Application Support` reads `Application%20Support`; compare with `path(percentEncoded: false)`.

Plain `swift test` lets warnings through; the AGENTS.md test command adds `-Xswiftc -warnings-as-errors`, as CI does ([[decisions/0014-build-and-ci-foundation]]).

Open design point in SPEC §9, to settle in the task named:
- **The coordinator cannot see GitHub.** SPEC §9.1 draws `RefreshCoordinator → GitHubService`, but NFR-17 forbids the core importing GitHub. The coordinator needs a neutral seam for polled work (a `SchedulePolicy` plus an async refresh), which the app fills with GitHub. Decide in T-2.6, before T-3.6.

## Related
[[decisions/0004-logic-in-contribusagekit-package]] · [[decisions/0005-json-file-persistence]] · [[decisions/0010-provider-abstraction-from-day-one]] · [[modules/test-support]]
