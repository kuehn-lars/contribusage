---
type: decision
status: accepted
updated: 2026-10-03
aliases: [ADR-030]
tags: [core, provider, diagnostics]
tracks: [App/Popover/PopoverView.swift, App/AppState+Copy.swift, App/Settings/SettingsView.swift, Packages/ContribusageKit/Sources/ContribusageCore/Providers/Provider.swift, Packages/ContribusageKit/Sources/ContribusageClaudeCode/ClaudeCodeProvider.swift]
---
# ADR-030: Provider diagnostics through `UsageProvider.diagnostics()`; diagnostics in Settings, statistics in the popover

- **Decided:** 2026-10-03 · **Spec:** SPEC §10.2, §11.2, §13, FR-36, FR-42, US-10, T-5.5 · **Supersedes:** —

## Context
US-10 asks "Copy diagnostics" for provider specific facts: for Claude Code the located `claude` (path, version, executable type), the last probe's exit code and its raw `/usage` output. The SPEC §10.2 protocols had no way to ask a provider for them, and only the provider knows them.

## Options
| Option | For | Against |
|---|---|---|
| App casts to `ClaudeCodeProvider` (as the Providers tab does) | No contract change | Every provider adds a cast in the app; the app holds provider knowledge |
| `diagnostics() async -> [String]` on `UsageProvider`, default `[]` | Any provider adds its lines in its own target; testable there | One more protocol requirement in §10.2 |

## Decision
`UsageProvider` gains `func diagnostics() async -> [String]`, with an empty default in the core. It may run the provider's detection, never a fetch, and holds no secret. Claude Code returns the `claude` the probe runs, located as the Providers tab does when no probe has run since launch (the registry detects only on first run, and a fresh cached snapshot delays the first probe, so a cache-only read said "not located"), and the last probe's exit code and stdout. Two copy actions for two readers: Copy Diagnostics in Settings' Advanced tab holds the technical state for a bug report; Copy statistics, a plain popover footer button labelled Copy (FR-42), holds what the popover shows, for sharing the numbers. FR-36's footer overflow menu with diagnostics was built and dropped in review: one item behind ⋯ hid it, and the popover is about the numbers, not the internals. The statistics lines come from the same helpers the views draw (`ActivitySection.Figures`, `GitHubReport.statsText`, the core's `UsageWindow` texts), so the copy cannot drift from the screen. The app composes the text: app, macOS and chip, per provider its enabled flag, `SourceState.diagnostics` per source, skipped lines, the provider's lines, then GitHub.

## Consequences
- Diagnostics stay English in every language, since they go into bug reports; copied statistics follow the popover's language ([[decisions/0031-string-catalogs]]), and since T-5.15 its block order, section order and hidden sections.
- "Last error per source" is the current state's error; an error a later success replaced is gone.
- A provider that has not probed since launch reports "Last probe: none since launch"; a probe that timed out keeps the previous result.
- GitHub switched off (T-5.14) keeps its last state, so its diagnostics line still reports that state.
- Copying diagnostics for a disabled provider may run `claude --version`, as opening the Providers tab already does.
- Claude Code's diagnostics lines stay English after [[decisions/0033-provider-tool-texts]]: `toolText` serves the popover, Copy statistics and notifications, never diagnostics.
- Copy statistics gives the heatmap one line per layer with its 26 week total, through the core's `HeatmapLayer.text` the tooltips use (T-5.16).
- The menu bar mode and provider (T-5.10, Settings' General tab) appear in neither Copy statistics nor diagnostics; Copy follows the popover.
