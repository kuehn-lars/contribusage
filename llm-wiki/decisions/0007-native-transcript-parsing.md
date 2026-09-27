---
type: decision
status: accepted
updated: 2026-09-28
aliases: [ADR-007]
tags: [claude-code, activity]
---
# ADR-007: Parse Claude Code transcripts natively; `ccusage` only for validation

- **Decided:** 2026-09-28 · **Spec:** SPEC §8.3 · **Supersedes:** —

## Context
Activity numbers come from the JSONL transcripts Claude Code writes. `ccusage` already aggregates them.

## Options
| Option | For | Against |
|---|---|---|
| Native incremental parser | No Node.js runtime; reads only appended lines | Must track an undocumented format |
| Shell out to `ccusage --json` | Existing, maintained logic | Runtime dependency; full rescans; a second process on every change |

## Decision
A native, lenient, incremental parser in the provider target. `ccusage` serves as the reference implementation: daily token totals must match within 1 % (SPEC §8.3.6).

## Consequences
- The transcript format is undocumented; R-3 verifies it before implementation and the decoder tolerates unknown fields.
- The generic `IncrementalJSONLReader` and `HistoryStore` live in the core for future providers.
