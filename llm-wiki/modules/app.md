---
type: module
status: active
updated: 2026-09-29
tracks: [App, Contribusage.xcodeproj]
tags: [app, swiftui, ui]
---
# App target

The thin SwiftUI shell: menu bar label, popover, Settings, `AppState`, provider registration and notification delivery. It holds views and wiring only; parsing and business logic live in the package ([[decisions/0004-logic-in-contribusagekit-package]]).

## Spec
- **Sections:** SPEC §9.2 (responsibilities), §9.3 (concurrency), §11 (UI), §15.3 and §15.5 (project and entry point), §20 (pitfalls: Settings activation, `MenuBarExtra`, template labels, the notch, notifications, `SMAppService`)
- **Requirements:** FR-4, FR-12, FR-30 to FR-37; NFR-3, NFR-8 to NFR-10, NFR-16
- **Tasks:** T-1.1, T-1.7, T-2.7, T-3.2, T-3.5, T-4.6 (UI), T-5.2 to T-5.5, T-5.7, T-5.10
- **Path:** `App/` and `Contribusage.xcodeproj`

## Depends on
[[modules/core]], [[modules/claude-code]] and [[modules/github]]. `App/ProviderRegistration.swift` is the only place that lists providers.

## Contract
Built so far (T-1.1): a `MenuBarExtra` with a Quit item. Build settings per SPEC §15.3: `ARCHS = arm64`, macOS 14.0, warnings as errors, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, generated Info.plist with `LSUIElement`, hardened runtime, ad-hoc signing. `App/` is a synchronised folder: new files join the target without project file edits ([[decisions/0014-build-and-ci-foundation]]). The popover shell (T-1.7, SPEC §11.2, §11.3): `AppState` holds one `ProviderGroupState` (descriptor plus optional limits and activity `SourceState`) per enabled provider and a GitHub `SourceState`. `Popover/SectionStateView` draws every §11.3 state around a section's content: the first load is the placeholder value `.redacted(reason: .placeholder)`, stale and failed-with-previous values are dimmed (the age sits in every section's `SectionHeader`, so stale needs no extra line), `unparseable` adds "Show raw output". A per-minute `TimelineView` in `PopoverView` sets the `now` environment value that ages and countdowns read. Provider groups sit in a `ScrollView` whose height is the groups' measured height, capped by the screen; GitHub and the footer (Refresh ⌘R, Quit ⌘Q) stay pinned. `Popover/AppState+Mock.swift` holds mock data and one preview per §11.3 row (plus a passed reset), light and dark side by side. Live wiring (T-2.7): `AppState.live()` builds the `ProviderRegistry` from `ProviderRegistration.all(time:)` (the `ClaudeCodeProvider` with `LiveProcessRunner`, the login shell from `$SHELL` or `/bin/zsh`, and the `provider.claude-code.pathOverride` default read on every resolution) and the `enabledProviders` default, which it writes back once settled (FR-2); it creates one group per enabled provider in `loading`, then starts the `RefreshCoordinator`, whose updates it applies on the main actor. `SystemConditions` turns `NSWorkspace` sleep and wake, `NWPathMonitor` and `NSProcessInfoPowerStateDidChange` into `ScheduleConditions`, which reach `update(_:)` in order through one `AsyncStream` consumer. `PopoverView.onAppear` reports the popover opening; Refresh and the limits section's Retry call `refreshNow()`; `SectionStateView` takes an optional `retry` closure and shows Retry only with one. `LimitsSection` draws the §11.4 bar (empty after a reset) and the core's window texts (`UsageWindow+Display`, hover: absolute date and time), and one VoiceOver element per window with the §11.7 label; error lines use the §13 wording with the provider's name. Buttons still inert: Locate… (T-5.2), Connect GitHub (T-3.2); GitHub stays `notConfigured` until its client is wired (T-3.6), and its errors show no Retry until then. The heatmap is T-3.5; the footer's Settings and ⋯ items come with the Settings scene and diagnostics.

## Things that bite
- `ImageRenderer` draws AppKit-backed controls (`ProgressView`, borderless buttons) as placeholders, so the limits bar is a drawn `Capsule`; that also keeps the §11.4 colours exact.
- `xcodebuild` needs a full Xcode selected; the Command Line Tools build the package but not the app.
- `MenuBarExtra` has no "is open" signal (SPEC §20); the popover-open trigger relies on `onAppear` of the window content firing on every open, which still needs a manual check (no automated way to click the menu bar item here).
- In the `MenuBarExtra` window a `ScrollView` has no height of its own: a `ViewThatFits` over groups and a scroll view fell back to the scroll view and drew the groups at zero height once they arrived asynchronously (the mock data had hidden it). Hence the measured height.
- Foundation's duration formatting rounds under 30 s to "0 min", hence the 1 min floor in the reset text; en_US abbreviates hours as "hr", not SPEC's "h".
- SPEC §15.5 registers a `DebugFakeProvider` under `CONTRIBUSAGE_FAKE_PROVIDER`, but `FakeProvider` lives in `ContribusageTestSupport`, which is not a product and never links into the app. Decide in T-5.9 where the debug provider lives.

## Related
[[decisions/0001-native-swift-swiftui]] · [[decisions/0006-no-app-sandbox]] · [[decisions/0008-minimum-macos-14]] · [[decisions/0009-apple-silicon-only]]
