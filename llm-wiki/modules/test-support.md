---
type: module
status: active
updated: 2026-10-03
tracks: [Packages/ContribusageKit/Tests/ContribusageTestSupport]
tags: [testing]
---
# ContribusageTestSupport

Shared test code that never ships: a fake for every support seam, the `FakeProvider` and the provider conformance suite. `FakeProvider` is shaped unlike Claude Code on purpose (one weekly window, pushed limits only, input and output tokens only), so the core cannot quietly depend on Claude Code's shape.

## Spec
- **Sections:** SPEC §10.6 (seams), §16.1 to §16.4 (levels, fixtures, must-have cases, conformance suite)
- **Requirements:** US-11; NFR-15
- **Tasks:** T-1.4, T-1.6, T-5.12
- **Path:** `Packages/ContribusageKit/Tests/ContribusageTestSupport/`; fixtures live in each test target's `Fixtures/`

## Depends on
[[modules/core]] only.

## Contract
Built so far: `ProviderID.fake`, the ID the `FakeProvider` carries, and a fake per seam protocol (`Fakes.swift`), each thread safe through `OSAllocatedUnfairLock` (macOS 14 has no `Mutex`): `FakeTimeSource` (settable, `advance(by:)`), `FakeProcessRunner` and `FakeHTTPTransport` (answer from a handler, record `requests`; a sleeping handler is the never-finishing process of SPEC §16.4), `FakeSecretStore` (in memory), `FakeFileEvents` (`send(_:)` to every open stream, `activeStreams` drops when a consumer is cancelled), `FakeFileReader` (below). `AppPaths` needs no fake: tests pass a temporary root, `AppPaths.temporary()` (a fresh, not yet created `contribusage-<UUID>/root/`, [[decisions/0015-app-paths-struct]]). `FakeProvider` (T-1.6): settable `availability` and a `detections` count for registry tests, an injectable `fetch` (failing by default: its limits are push only, and `pushedUpdates()` yields the one weekly window on subscription), and an activity source that watches through a `FakeFileEvents` and emits one report on start and per change. `ProviderConformance.check(_:neverFinishing:failing:fileEvents:)` runs the SPEC §16.4 checks per capability and records violations as Swift Testing issues at the caller's line; the extra wirings are required only for the capabilities a provider has (`activityOnlyProviderPassesTheConformanceSuite`); the target imports `Testing` and `AppKit` (SF Symbol lookup). `FakeFileReader` passes through to the real (temporary) disk and records every URL listed or read in `reads`; `check` takes it with the declared `readRoots` (required with activity, like `fileEvents`) and, after the first activity report, records an issue when nothing was read through the seam or a read lies outside them, symlinks resolved on both sides and whole path components compared (a path that does not exist is not resolved, so a missing file spelled through `/private` can be flagged: loud, not silent) ([[decisions/0025-read-roots-check-with-t-4-7]]). Child processes and writes are not covered. `FakeProvider` takes a `fileReader` and paths to read through it, which `conformanceSuiteRejectsAReadOutsideTheRoots`, `conformanceSuiteRejectsAnActivitySourceThatReadsNothing` and `conformanceSuiteResolvesSymlinks` use to keep this check able to fail and honest. `conformanceSuiteRejectsABrokenProvider` keeps the suite able to fail. The target is a regular (non-test) target under `Tests/`, so test targets can depend on it while no product ships it.

## Related
[[decisions/0010-provider-abstraction-from-day-one]]
