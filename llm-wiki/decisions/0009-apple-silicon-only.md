---
type: decision
status: accepted
updated: 2026-10-04
aliases: [ADR-009]
tags: [platform]
---
# ADR-009: Apple Silicon (arm64) only

- **Decided:** 2026-09-28 · **Spec:** SPEC §1.3, NFR-16, §15.3, §20 · **Supersedes:** —

## Context
Each architecture multiplies the test matrix, the performance baselines and the binaries to sign and verify.

## Options
| Option | For | Against |
|---|---|---|
| arm64 only | One test matrix, one performance baseline (M1), nothing extra to sign | Intel Macs cannot run the app |
| Universal binary | Runs on Intel Macs | Double testing effort for a shrinking platform |

## Decision
Build with `ARCHS = arm64` in every configuration; CI checks the Release executable with `lipo -archs`.

## Consequences
- Xcode's "Standard Architectures" would silently add x86_64 in Release; the explicit setting and the CI check prevent that (SPEC §20).
- `claude` installations built for x86_64 still need Rosetta; diagnostics report the executable type (FR-36). Without Rosetta such a `claude` shows as not found: the M4 check (2026-10-04) dropped SPEC §13's Rosetta message and its §16.5 row, since only a migration from an Intel Mac leads there.
