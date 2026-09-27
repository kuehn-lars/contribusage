---
type: decision
status: accepted
updated: 2026-09-28
aliases: [ADR-002]
tags: [claude-code, limits]
---
# ADR-002: The `/usage` probe is the primary Claude Code limits source

- **Decided:** 2026-09-28 · **Spec:** SPEC §8.1, §8.2, FR-7 · **Supersedes:** —

## Context
Plan limits have to come from an official interface ([[decisions/0003-official-interfaces-only]]). Claude Code exposes them in two places: the `/usage` command and the `rate_limits` field of its status line JSON.

## Options
| Option | For | Against |
|---|---|---|
| `claude -p "/usage" --no-session-persistence` | Official binary; works without an open session; shows every window, including model-specific ones | Human-oriented text with no format guarantee; each probe starts a process |
| Status line only | Pushed after every assistant message, no extra process | Needs an active session; carries only two windows |

## Decision
The probe is the primary source. The status line bridge is an optional second source of the same provider, merged per label with the newest observation winning (FR-39).

## Consequences
- The parser must be generic and fixture-tested per Claude Code version, with raw output as a fallback (SPEC §8.1.5, §16.6).
- Whether a probe consumes plan quota is open (R-1), so the default interval stays conservative at 15 minutes (NFR-5).
- Probes run in an empty folder with `--no-session-persistence`, so they neither run project configuration nor show up as sessions.
