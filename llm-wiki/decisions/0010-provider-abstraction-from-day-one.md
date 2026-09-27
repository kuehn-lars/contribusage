---
type: decision
status: accepted
updated: 2026-09-28
aliases: [ADR-010]
tags: [architecture, providers]
---
# ADR-010: Provider abstraction from day one

- **Decided:** 2026-09-28 · **Spec:** SPEC §7, §9.1, §10.2, NFR-17 · **Supersedes:** —

## Context
v1 integrates only Claude Code, but more AI coding tools are planned (G-7). Persistence paths, settings keys and notification keys are hard to change after release.

## Options
| Option | For | Against |
|---|---|---|
| Provider-neutral core, one package target per provider | Compile-time isolation keeps Claude Code assumptions out of the core; stable keys from the start | More types and protocols up front |
| Hard-wire Claude Code now, refactor later | Less code today | Costly and risky migration of persistence and notification keys |

## Decision
The core knows only provider protocols and neutral types. Each provider is its own target that depends only on the core, and the app is the only place that registers providers.

## Consequences
- A deliberately different `FakeProvider` and a shared conformance suite keep the abstraction honest ([[modules/test-support]]).
- `SourceError.providerSpecific` is the escape hatch for errors the neutral model cannot express.
