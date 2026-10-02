---
type: decision
status: accepted
updated: 2026-10-02
aliases: [ADR-023]
tags: [core, claude-code, app, insights]
tracks: [Packages/ContribusageKit/Sources/ContribusageCore/Providers/Reports.swift, Packages/ContribusageKit/Sources/ContribusageClaudeCode/Limits/UsageParser.swift, App/Popover/ProviderGroup.swift]
---
# ADR-023: Insights are parsed into periods, not shown verbatim

- **Decided:** 2026-10-01 · **Spec:** SPEC FR-8, FR-38, US-8, P-11, §7.2, §10.3, T-6.1 · **Supersedes:** —

## Context
FR-38 showed the `/usage` "What's contributing" block verbatim in a disclosure group. In the 360 pt popover the text wraps mid-name, long ranked lists run into paragraphs, and the three-line caveat pushes the numbers down: nothing is sorted by importance.

## Options
| Option | For | Against |
|---|---|---|
| Keep the verbatim `String`, restyle the text | No model change | Layout stays at the mercy of the CLI's wrapping; nothing can be ranked or cut |
| Parse in the app view | No core change | The app holds views only; the format is Claude Code's, so the parse belongs to its provider |
| Neutral `Insights` type in the core, filled by the provider's parser | Testable parse, any provider can supply it, the view lays out rows | `state.json` schema bump; the parse can drift with the CLI |

## Decision
`LimitsReport.insights` is an `Insights` value: an optional note and periods, each with a summary, shares and ranked lists (SPEC §10.3). `UsageParser` fills it by P-11; a line that fits no rule is kept as a share without a percent, so nothing is dropped, and a block without a period yields no `Insights`, so every value has at least one period and the view needs no guard. The popover shows one period at a time behind a segmented picker (selected by label, so the choice survives a refresh), the shares, the top three of each ranking, and the note as the tooltip of the "Insights" title (`InsightsSection` in `App/Popover/ProviderGroup.swift`).

## Consequences
- `state.json` moves to schema version 2; an older cache is discarded once, as SPEC §10.7 prescribes for unknown versions.
- A changed CLI wording degrades to unlabelled lines rather than a missing section; `rawOutput` still holds the verbatim text.
- Settings' Advanced tab hides the area with `showInsights` (on by default, [[decisions/0028-settings-scope-and-wiring]]).
- Revisit when the CLI changes the block's shape, or when a second provider's insights do not fit periods.
