---
type: decision
status: accepted
updated: 2026-09-29
aliases: [ADR-016]
tags: [core, providers, concurrency]
tracks: [Packages/ContribusageKit/Sources/ContribusageCore/Providers/Provider.swift]
---
# ADR-016: `ActivitySource` watches while its stream is consumed

- **Decided:** 2026-09-28 · **Spec:** SPEC §10.2, §16.4, T-1.6 · **Supersedes:** —

## Context
SPEC §10.2 sketched `ActivitySource` with `start()`, `stop()`, `rescan()` and `reports()`. The four carry ordering rules a caller must learn (start before consuming, stop exactly once, what `reports()` does after `stop()`), and every provider would have to implement them the same way. `FileEvents` already stops watching when its consumer is cancelled.

## Options
| Option | For | Against |
|---|---|---|
| `start`, `stop`, `rescan`, `reports()` | As sketched | Lifecycle state in every provider; a forgotten `stop()` leaks file handles |
| `reports()` starts watching, cancelling its consumer stops it; `rescan()` | Lifetime is the consuming task's; no states to get wrong; matches `FileEvents` | A caller that wants to pause watching cancels and later re-subscribes, getting a fresh initial report |

## Decision
`ActivitySource` has `reports()` and `rescan()`. Subscribing starts the watching and emits an initial report; cancelling the consumer stops it and releases every file handle.

## Consequences
- The conformance check "`stop()` releases all file watching" became "cancelling the consumer of `reports()` releases all file watching" (SPEC §16.4).
- Disabling a provider (FR-2) is cancelling the task that consumes its stream.
- Revisit if a source needs to keep state across a pause that a re-subscription cannot rebuild cheaply.
