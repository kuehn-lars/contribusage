---
type: decision
status: accepted
updated: 2026-10-03
aliases: [ADR-033]
tags: [localization, providers, claude-code]
tracks: [Packages/ContribusageKit/Sources/ContribusageCore/Providers/Provider.swift, Packages/ContribusageKit/Sources/ContribusageClaudeCode/ClaudeCodeProvider.swift, Packages/ContribusageKit/Sources/ContribusageClaudeCode/Resources, Packages/ContribusageKit/Sources/ContribusageCore/Notifications/NotificationPlanner.swift]
---
# ADR-033: Providers translate the known texts their tool prints, at display time

- **Decided:** 2026-10-03 · **Spec:** FR-5, FR-38, NFR-10, SPEC §7.3, §8.1.4 P-4, §10.2 · **Supersedes:** part of [[decisions/0031-string-catalogs]] ("providers add no strings", window labels as printed)

## Context
[[decisions/0031-string-catalogs]] left every text a tool prints in English, so a German popover read "Current session" and notifications "Claude Code: Current session bei 80 %". The window labels are a small, documented set (SPEC §8.1.4 P-4); so are the insights' period labels (`Last 24h`, `Last 7d`) and the counts in a period's summary (`668 requests · 8 sessions`). The note is two fixed sentences. The shares, rankings and billing note are free text the tool rewords, with names of skills and plugins inside. The label is also the window's identity: the popover's `ForEach` id and the notification cycles in `state.json` are keyed by it (FR-15), so a translated label stored at parse time would re-arm notifications after a language change.

## Options
| Option | For | Against |
|---|---|---|
| Translate at parse time into `UsageWindow.label` | No new plumbing | Changes the persisted key with the language; snapshots keep the old language |
| A second `title` field set by the parser | Key stays raw | Persisted title freezes the language until the next probe; touches the shared report type |
| `ProviderDescriptor.toolText` closure, applied where a printed text is shown | Key stays raw; the table lives in the provider target with its own catalog; follows the language at once | Every display site calls it |
| Window labels in the core's catalog | One catalog fewer | Claude Code wording in the provider neutral core (ADR-010) |

## Decision
`ProviderDescriptor` carries `toolText: (String) -> String`, default as printed. Claude Code maps through its own String Catalog (`ContribusageClaudeCode/Resources`): the window labels `Current session`, `Current week (all models)` and `Current week (<model>)`, the periods `Last <n>h` and `Last <n>d`, the summary parts `<n> requests` and `<n> sessions` (a summary is split at ` · ` and translated part by part; plurals are catalog substitutions), and the two sentences of the insights note (a text is split into sentences at `. `; the first sentence is matched with `;` or ` —`, both of which the tool has printed). The fixed texts (both window labels without a model, both note sentences) are `manual` catalog keys looked up as printed, which `xcstringstool sync` keeps; the patterns are literal `LocalizedStringResource`s the build extracts, so the CI catalog check covers them; anything else stays as printed. The popover, its VoiceOver label, Copy statistics and the notification titles show the translation; the printed text stays the key everywhere (window cycles, `ForEach` ids, the picked period). Shares, rankings and the billing note stay as printed.

## Consequences
- `NotificationPlanner.plan` requires `windowTitle`; the coordinator passes the provider's `toolText`.
- A new fixed text is a catalog entry with `extractionState: manual`, no code; a new pattern needs a branch with a literal key.
- The lookup takes a `Locale` (default `.current`, the app's language), which is how the tests read German from the package bundle. CI's SwiftPM copies the catalog into the bundle uncompiled (the app build compiles it), so `ToolTextTests` run only where the bundle has a `de` localization; on CI the catalog check covers the translations.
- A new text the tool prints shows in English until the table learns it; a model name inside `Current week (…)` and an unknown summary part stay as printed.
- The same change replaced the core catalog's German "Reset in %@" and "Reset %@" with "Zurücksetzung in %@" and "Zurücksetzung %@".
- Revisit if the tool localizes its own output: then the labels arrive translated and the table matches nothing.
