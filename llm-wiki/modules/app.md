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
Built so far (T-1.1): a `MenuBarExtra` with a Quit item. Build settings per SPEC §15.3: `ARCHS = arm64`, macOS 14.0, warnings as errors, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, generated Info.plist with `LSUIElement`, hardened runtime, ad-hoc signing. `App/` is a synchronised folder: new files join the target without project file edits ([[decisions/0014-build-and-ci-foundation]]). The three package products are linked but not yet imported.

## Things that bite
- `xcodebuild` needs a full Xcode selected; the Command Line Tools build the package but not the app.
- SPEC §15.5 registers a `DebugFakeProvider` under `CONTRIBUSAGE_FAKE_PROVIDER`, but `FakeProvider` lives in `ContribusageTestSupport`, which is not a product and never links into the app. Decide in T-5.9 where the debug provider lives.

## Related
[[decisions/0001-native-swift-swiftui]] · [[decisions/0006-no-app-sandbox]] · [[decisions/0008-minimum-macos-14]] · [[decisions/0009-apple-silicon-only]]
