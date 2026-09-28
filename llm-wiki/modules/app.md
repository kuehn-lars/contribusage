---
type: module
status: active
updated: 2026-09-28
tracks: [App, Contribusage.xcodeproj]
tags: [app, swiftui, ui]
---
# App target

The thin SwiftUI shell: menu bar label, popover, Settings, `AppState`, provider registration and notification delivery. It holds views and wiring only; parsing and business logic live in the package ([[decisions/0004-logic-in-contribusagekit-package]]).

## Spec
- **Sections:** SPEC §9.2 (responsibilities), §9.3 (concurrency), §11 (UI), §15.3 and §15.5 (project and entry point), §20 (pitfalls: Settings activation, `MenuBarExtra`, template labels, the notch, notifications, `SMAppService`)
- **Requirements:** FR-4, FR-12, FR-30 to FR-37; NFR-3, NFR-8 to NFR-10, NFR-16
- **Tasks:** T-1.1, T-1.7, T-2.7, T-2.8, T-3.2, T-3.5, T-4.6 (UI), T-5.2 to T-5.5, T-5.7
- **Path:** `App/` and `Contribusage.xcodeproj`

## Depends on
[[modules/core]], [[modules/claude-code]] and [[modules/github]]. `App/ProviderRegistration.swift` is the only place that lists providers.

## Contract
Built so far (T-1.1): a `MenuBarExtra` with a Quit item. Build settings per SPEC §15.3: `ARCHS = arm64`, macOS 14.0, warnings as errors, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, generated Info.plist with `LSUIElement`, hardened runtime, ad-hoc signing. `App/` is a synchronised folder: new files join the target without project file edits ([[decisions/0014-build-and-ci-foundation]]). The popover shell (T-1.7, SPEC §11.2, §11.3): `AppState` holds one `ProviderGroupState` (descriptor plus optional limits and activity `SourceState`) per enabled provider and a GitHub `SourceState`. `Popover/SectionStateView` draws every §11.3 state around a section's content: the first load is the placeholder value `.redacted(reason: .placeholder)`, stale and failed-with-previous values are dimmed (the age sits in every section's `SectionHeader`, so stale needs no extra line), `unparseable` adds "Show raw output". A per-minute `TimelineView` in `PopoverView` sets the `now` environment value that ages and countdowns read. Provider groups sit in a `ViewThatFits` that falls back to a `ScrollView`; GitHub and the footer (Refresh ⌘R, Quit ⌘Q) stay pinned. `Popover/AppState+Mock.swift` holds mock data and one preview per §11.3 row, light and dark side by side; the running app shows the mock until the coordinator feeds `AppState` (T-2.6). Buttons other than Quit are no-ops until their tasks (Retry, Refresh: T-2.6; Locate…: T-5.2; Connect GitHub: T-3.2). Exact reset and age wording is T-2.7, the heatmap T-3.5; the footer's Settings and ⋯ items come with the Settings scene and diagnostics.

## Things that bite
- `ImageRenderer` draws AppKit-backed controls (`ProgressView`, borderless buttons) as placeholders, so the limits bar is a drawn `Capsule`; that also keeps the §11.4 colours exact.
- `xcodebuild` needs a full Xcode selected; the Command Line Tools build the package but not the app.
- SPEC §15.5 registers a `DebugFakeProvider` under `CONTRIBUSAGE_FAKE_PROVIDER`, but `FakeProvider` lives in `ContribusageTestSupport`, which is not a product and never links into the app. Decide in T-5.9 where the debug provider lives.

## Related
[[decisions/0001-native-swift-swiftui]] · [[decisions/0006-no-app-sandbox]] · [[decisions/0008-minimum-macos-14]] · [[decisions/0009-apple-silicon-only]]
