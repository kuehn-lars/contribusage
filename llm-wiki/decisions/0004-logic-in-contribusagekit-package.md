---
type: decision
status: accepted
updated: 2026-09-28
aliases: [ADR-004]
tags: [architecture, testing]
---
# ADR-004: All logic lives in the local `ContribusageKit` package

- **Decided:** 2026-09-28 · **Spec:** SPEC §9, §15.2, §15.4 · **Supersedes:** —

## Context
Parsing, statistics and scheduling carry most of the risk and need fast, fixture-based tests (principle 7). An Xcode app target can only be tested through Xcode.

## Options
| Option | For | Against |
|---|---|---|
| Local Swift package with one target per concern | `swift test` from the command line; fast agent loop; separation enforced by the target graph | Two build systems (SwiftPM and Xcode) |
| Logic in the app target | One place for everything | Slow, UI-bound tests; nothing stops layers from mixing |

## Decision
Everything except views and wiring lives in `Packages/ContribusageKit`; the app target stays thin.

## Consequences
- The core's independence from providers is checkable from `Package.swift` (NFR-17).
- Package targets have no default MainActor isolation, which keeps blocking work off the main actor by default (SPEC §20).
