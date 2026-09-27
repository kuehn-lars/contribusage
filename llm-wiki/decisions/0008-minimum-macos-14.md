---
type: decision
status: accepted
updated: 2026-09-28
aliases: [ADR-008]
tags: [platform]
---
# ADR-008: Minimum macOS 14 Sonoma

- **Decided:** 2026-09-28 · **Spec:** SPEC header, NFR-16, §15.3 · **Supersedes:** —

## Context
The deployment target decides which SwiftUI and Observation APIs are available.

## Options
| Option | For | Against |
|---|---|---|
| macOS 14 | Observation framework, `openSettings`, modern SwiftUI; every Apple Silicon Mac can run it | Excludes Macs that stay on 13 |
| macOS 13 | Slightly wider reach | `ObservableObject` everywhere, fewer SwiftUI APIs |

## Decision
`LSMinimumSystemVersion` and `MACOSX_DEPLOYMENT_TARGET` are 14.0.

## Consequences
`AppState` uses `@Observable`; Settings opens through `@Environment(\.openSettings)`.
