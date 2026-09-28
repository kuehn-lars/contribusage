---
type: module
status: active
updated: 2026-09-28
tracks: [Packages/ContribusageKit/Tests/ContribusageTestSupport]
tags: [testing]
---
# ContribusageTestSupport

Shared test code that never ships: a fake for every support seam, the `FakeProvider` and the provider conformance suite. `FakeProvider` is shaped unlike Claude Code on purpose (one weekly window, pushed limits only, input and output tokens only), so the core cannot quietly depend on Claude Code's shape.

## Spec
- **Sections:** SPEC §10.6 (seams), §16.1 to §16.4 (levels, fixtures, must-have cases, conformance suite)
- **Requirements:** US-11; NFR-15
- **Tasks:** T-1.4, T-1.6, T-5.9
- **Path:** `Packages/ContribusageKit/Tests/ContribusageTestSupport/`; fixtures live in each test target's `Fixtures/`

## Depends on
[[modules/core]] only.

## Contract
Built so far: `ProviderID.fake`, the ID the `FakeProvider` will carry. The target is a regular (non-test) target under `Tests/`, so test targets can depend on it while no product ships it.

## Related
[[decisions/0010-provider-abstraction-from-day-one]]
