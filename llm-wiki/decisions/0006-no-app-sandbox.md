---
type: decision
status: accepted
updated: 2026-09-28
aliases: [ADR-006]
tags: [platform, distribution, security]
---
# ADR-006: No App Sandbox; distribution outside the Mac App Store

- **Decided:** 2026-09-28 · **Spec:** SPEC §1.3, §14, §15.3 · **Supersedes:** —

## Context
The app has to launch tool binaries such as `claude` and read the files those tools write (`~/.claude`).

## Options
| Option | For | Against |
|---|---|---|
| No sandbox, Developer ID signing and notarization | Can run the user's tools and read their files | No Mac App Store |
| Sandbox with security-scoped bookmarks | App Store eligible | Cannot launch arbitrary binaries |

## Decision
App Sandbox off, Hardened Runtime on, distributed as a notarized download.

## Consequences
- Without the sandbox, the app's own discipline is the boundary: it runs only resolved executables with argument arrays and reads only declared roots (SPEC §14).
- Release needs Developer ID signing and notarization (T-6.7).
