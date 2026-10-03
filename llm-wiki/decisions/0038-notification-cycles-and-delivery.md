---
type: decision
status: accepted
updated: 2026-10-04
aliases: [ADR-038]
tags: [notifications]
tracks: []
---
# ADR-038: Notification cycles tolerate a moving reset time; delivery spaced and grouped

- **Decided:** 2026-10-04 · **Spec:** SPEC FR-13, FR-15, FR-52, US-3, T-5.20 · **Supersedes:** —

## Context
`NotificationPlanner.plan` ends a window's cycle whenever the reported reset time differs at all from the stored one ([[decisions/0027-notification-planning-in-the-coordinator]]). In use, background probes produced a "has reset" notification followed by "at 80 %" again for windows that had not reset: both stored cycles were re-sent on the same probe, with reset times at `:59`. The `/usage` text prints the reset time at minute or hour precision, so the same reset can parse to different instants between two probes (P-7). Separately, two windows crossing a threshold in one refresh were posted in the same instant, and macOS showed only the last banner; one window crossing 80 and 95 at once posted two notes under one identifier.

## Options
- **Exact match (as built):** any change of the reset time is a new cycle. Fails on the drift above.
- **Cycle ends when its reset time has passed:** a reset time moving forward by a minute past the stored one ends the cycle wrongly at the boundary.
- **Tolerance:** reset times within 1 h are one cycle. Every window lasts at least 5 h, so a real reset moves the time by far more than 1 h.

## Decision
- A cycle ends only when the reported reset time differs from the cycle's by more than 1 h; a missing reset time on either side keeps the cycle (FR-15). The 8 day pruning still bounds a cycle without a reset time.
- One refresh notifies only the highest threshold a window crossed (FR-13).
- Delivery (FR-52): one note at a time, 3 s apart, in report order; `threadIdentifier` is the provider ID, so Notification Center stacks a provider's notes; identifiers stay per window and cycle.

## Consequences
- The rules are planner logic and tested there (SPEC §16.3); the spacing and grouping live in the app's delivery and are checked by hand.
- A window whose real reset moves by less than 1 h would not re-arm; no tool is known to have windows that short.
