---
type: decision
status: accepted
updated: 2026-10-02
aliases: [ADR-024]
tags: [claude-code, activity, persistence]
tracks: [Packages/ContribusageKit/Sources/ContribusageClaudeCode/Activity/TranscriptActivity.swift]
---
# ADR-024: The live index stays in memory until a measurement asks for more

- **Decided:** 2026-10-02 · **Spec:** SPEC §8.3.4, §10.7, T-4.6, T-4.7 · **Supersedes:** —

## Context
SPEC §8.3.4 described the live index (unique keys and their usage for the transcripts that exist) as "persisted for fast startup" in `providers/claude-code/live-index.json`, a cache whose loss is tolerable (§10.7). Persisting it means a second file format, a version, and a check that every remembered file is still the same file at launch, before anyone has measured how long the launch scan takes. T-4.7 measures exactly that, against a generated 500 MB fixture set (NFR-7).

## Options
| Option | For | Against |
|---|---|---|
| Persist the live index now | Launch skips re-reading old transcripts | Format, versioning and staleness checks for a cost nobody has measured |
| Keep it in memory, rebuild it on the first `reports()` subscription | No file to keep consistent; the transcripts stay the only truth | Every launch reads all transcripts once |

## Decision
The live index lives in memory only (`TranscriptActivity`, [[modules/claude-code]]: the first line per key, SPEC §8.3.4) and is rebuilt from the transcripts when the first `reports()` stream starts. `live-index.json` is not written.

## Consequences
- The history store ([[decisions/0005-json-file-persistence]]) is unaffected: frozen days persist as before, so a deleted transcript still keeps its history.
- T-4.7 measured the launch scan of a generated 520 MB set at 1.5 to 1.7 s in a release build on an M3 (3.1 to 3.9 s before the memory fix), well inside NFR-7 by the rule of [[decisions/0026-nfr-7-on-an-m3]] ([[research/nfr-7-transcript-scan]]). The index stays in memory, and `live-index.json` is gone from SPEC §10.7.
- Revisit if a measurement on real data, or a much larger transcript tree, gets close to the budget.
