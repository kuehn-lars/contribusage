---
type: decision
status: accepted
updated: 2026-09-28
aliases: [ADR-005]
tags: [persistence]
---
# ADR-005: JSON files for persistence

- **Decided:** 2026-09-28 · **Spec:** SPEC §10.7 · **Supersedes:** —

## Context
The app persists little: last snapshots, notification keys, a per-file read index and 365 days of daily aggregates per provider.

## Options
| Option | For | Against |
|---|---|---|
| Versioned JSON files | Small data, inspectable by hand, easy to version | No queries; whole-file writes |
| SwiftData or Core Data | Framework support | Heavy for this size; migrations are opaque |
| SQLite | Queries, partial writes | A dependency and a schema for little data |

## Decision
Atomic JSON files with a `schemaVersion`, one folder per provider under Application Support.

## Consequences
- Cache files of unknown or newer versions are discarded; `history.json` never is, and is backed up before migrations.
- Deleting a provider's data is deleting its folder (US-12).
