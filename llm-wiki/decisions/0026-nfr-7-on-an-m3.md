---
type: decision
status: accepted
updated: 2026-10-02
aliases: [ADR-026]
tags: [performance, testing, activity]
tracks: [Packages/ContribusageKit/Tests/ContribusageClaudeCodeTests/TranscriptActivityPerformanceTests.swift]
---
# ADR-026: NFR-7 is checked on an M3 against half its budget

- **Decided:** 2026-10-02 · **Spec:** SPEC NFR-7, T-4.7 · **Supersedes:** —

## Context
NFR-7 sets the scan budget for an Apple M1, the slowest supported chip ([[decisions/0009-apple-silicon-only]]). T-4.7 runs the performance test, and the machine it runs on is an M3. The M3's per-core speed is higher than the M1's, but by well under a factor of two, and the scan runs on one utility-QoS task.

## Options
| Option | For | Against |
|---|---|---|
| Measure on M1 hardware | Exactly what NFR-7 names | No M1 available |
| A manual CI job on GitHub's arm64 macOS runner | Reproducible, slower hardware | Virtualised and shared, so timings vary; 500 MB generated per run |
| Measure on the M3 against half the budget | Runs where development happens; the factor two covers the M1/M3 gap | A proxy, not the M1 itself |

## Decision
The opt-in performance test asserts NFR-7's limits. NFR-7 counts as met for an M1 when the release cold scan on the M3 takes at most 15 s, half of the 30 s budget, and the incremental update at most 100 ms.

## Consequences
- Results and margins: [[research/nfr-7-transcript-scan]].
- Revisit when an M1 is at hand or a measurement lands close to the half-budget line.
