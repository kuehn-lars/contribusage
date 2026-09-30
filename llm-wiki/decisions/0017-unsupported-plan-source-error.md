---
type: decision
status: accepted
updated: 2026-10-01
aliases: [ADR-017]
tags: [core, providers, errors]
tracks: [Packages/ContribusageKit/Sources/ContribusageCore/Providers/Reports.swift]
---
# ADR-017: `SourceError.unsupportedPlan` carries P-10 out of `fetch()`

- **Decided:** 2026-09-29 · **Spec:** SPEC §10.1, §13, P-10, T-2.5 · **Supersedes:** —

## Context
SPEC §13 maps "API key billing, no subscription" to `notConfigured(.unsupportedPlan)`, but a probe only learns this inside `LimitsSource.fetch()`, which can return a report or throw a `SourceError`. No `SourceError` case said "unsupported plan", and the provider-neutral coordinator (T-2.6) cannot read a Claude Code billing note to decide it.

## Options
| Option | For | Against |
|---|---|---|
| `providerSpecific(code: "unsupported-plan", …)` | No core change | The coordinator would string-match a provider's code to reach a neutral state |
| Return the report with zero windows | No core change | Indistinguishable from FR-9 unparseable output for anyone outside the provider |
| `SourceError.unsupportedPlan(note:)` | Mirrors `ProviderAvailability.unsupportedPlan` and `NotConfiguredReason.unsupportedPlan`; any provider can use it | One more case for every `switch` over `SourceError` |

## Decision
`SourceError` gains `unsupportedPlan(note: String)`. The coordinator shows it as `notConfigured(.unsupportedPlan(note:))`. Detection (FR-3) does not report `unsupportedPlan` for Claude Code: only a probe can tell, detection must stay cheap, and `ProviderRegistry` keeps `available` for the app's lifetime, so a note cached from a probe would never be read. SPEC P-10 says so.

## Consequences
- The popover's error line got one more message; T-2.6 does the mapping to `notConfigured`.
- Revisit if more "not configured" reasons start arriving through `fetch()`: then a separate result type beats growing the error enum.
