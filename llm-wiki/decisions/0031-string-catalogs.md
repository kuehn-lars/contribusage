---
type: decision
status: accepted
updated: 2026-10-03
aliases: [ADR-031]
tags: [app, core, localization]
tracks: [App/Resources/Localizable.xcstrings, Packages/ContribusageKit/Sources/ContribusageCore/Resources/Localizable.xcstrings, .github/workflows/ci.yml]
---
# ADR-031: String Catalogs in the app and the core, English and German, kept in sync by CI; tool text stays as printed

- **Decided:** 2026-10-03 · **Spec:** NFR-10, SPEC §11.3, §8.x.5 (provider template), §15, T-5.7 · **Supersedes:** —

## Context
NFR-10 wants every user facing string in a String Catalog, English first. Two targets build such strings: the app (views, error lines, Settings with its Popover tab, Copy statistics) and `ContribusageCore` (`UsageWindow.percentText` and `resetText`, shared by the popover, Copy and the T-5.10 menu bar label; `NotificationPlanner`'s titles). SPEC §11.3 said each provider supplies its own "not configured" and "unsupported plan" strings under `provider.<id>.` keys, but the v1 provider supplies none: the app words every `SourceError` and `NotConfiguredReason` once, with the provider's display name, and the unsupported plan text is the tool's own billing note ([[decisions/0017-unsupported-plan-source-error]]). Xcode's command line build extracts strings into `.stringsdata` files but writes nothing into a catalog; only the IDE syncs on build. Without a check, a new string silently misses its catalog. And macOS formats with the app's language: an app localized only in English runs as `en_DE` on a German Mac, so the region's conventions apply ("23 %", "1.234.567", 24 h) but weekdays and units stay English ("Mon", "2 hrs 10 min"); formatting with the user's language instead would put German words into English sentences.

## Options
| Option | For | Against |
|---|---|---|
| One catalog per target that builds strings: app and core | Each bundle owns its strings; SwiftPM compiles a package catalog, so `swift test` sees it; extraction covers both | The core gains a resource bundle; two catalogs |
| One app catalog, the core looks up `bundle: .main` | One file | Extraction never adds package strings, so nothing checks them; package tests run without that bundle |
| Move the core's texts into the app | No package resources | The texts serve three callers, and the planner's titles are planned and tested in the core |

## Decision
`App/Resources/Localizable.xcstrings` and `ContribusageCore/Resources/Localizable.xcstrings` (the package sets `defaultLocalization: "en"`; the core looks up `bundle: .module`). Strings built as `String` go through `String(localized:)` where they are built. Providers add no strings. Text a tool prints (window labels, the billing note, insights), technical detail (`SourceError.decoding`, `.io`) and product names are shown as received; diagnostics stay English because they go into bug reports. German ships alongside English (the project's region is `de`), so a German Mac gets German text and German dates; English and German plurals are catalog variations, not code. The NFR-10 build check is a CI step: it syncs a copy of each catalog against the release build's `.stringsdata` with `xcstringstool sync` and fails on any difference, which catches a missing key and a stale one, and it fails on any key meant for translation that has no German one.

## Consequences
- A new string needs a build in the Xcode IDE, or after `xcodebuild` the same `xcstringstool sync` on the catalog itself (the CI step shows the command). The copy must keep the name `Localizable.xcstrings`: sync matches the table by file name.
- Extracted keys that are not prose (`claude`, `github_pat_…`, `%@ · %@`) are marked `shouldTranslate: false` in the catalog.
- A provider that needs its own wording adds a catalog to its target and a `check` line to the CI step; Claude Code did so for its window labels ([[decisions/0033-provider-tool-texts]]), which partly supersedes "providers add no strings".
- Numbers follow the locale: `percentText` uses the locale's percent style ("23 %" in German), so the menu bar label (T-5.10) must reserve width for it, not for a fixed "100%".
- Every new string needs its German translation in the same change (the GitHub switch's subtitle, T-5.14, came with one); `shouldTranslate: false` exempts keys that are not prose.
- The SwiftPM test host is English only, so the core's lookups stay English in `swift test` on any Mac; tests need no language pinning.
- Text a tool prints stays English inside German sentences, except the known window labels, insights periods, counts and note since [[decisions/0033-provider-tool-texts]] ("Claude Code: Aktuelle Sitzung bei 80 %").
- A further language is a catalog edit, one more line in the CI check and a pseudo-localization run.
