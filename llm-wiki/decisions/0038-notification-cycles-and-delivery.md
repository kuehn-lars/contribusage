---
type: decision
status: accepted
updated: 2026-10-04
aliases: [ADR-038]
tags: [notifications]
tracks: [Packages/ContribusageKit/Sources/ContribusageCore/Notifications/NotificationPlanner.swift, App/Notifications/NotificationDelivery.swift]
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
- A window reported without a reset time ends the cycle once the cycle's reset time has passed: after a reset the tool can print a window without one (`<1% used`, P-9), and keeping the cycle would delay the reset note and the re-armed thresholds until the next printed time.
- A cycle keeps its first known reset time and takes the first one reported when it began without one. Following the printed time instead would change the notes' identifier mid-cycle, so the 95 % note would stand next to the 80 % one rather than replace it; a cycle that never took a reset time would only end by pruning.
- One refresh notifies only the highest threshold a window crossed (FR-13).
- Delivery (FR-52): one note at a time, 3 s apart, in report order; `threadIdentifier` is the provider ID, so Notification Center stacks a provider's notes; identifiers stay per window and cycle.

## Consequences
- The rules are planner logic and tested there (SPEC §16.3); the spacing and grouping live in the app's delivery and are checked by hand.
- The delivery queues notes on one stream and returns at once (the coordinator's `deliver` closure is synchronous, so the type says so), so the 3 s spacing never holds up the serialized refresh passes ([[decisions/0018-refresh-coordinator-shape]]); notes of refreshes that follow each other closely are spaced too.
- A time-only reset clause (P-7, not seen in real output so far) printed in its own minute resolves to the next day (P-8), a 24 h move that would end the cycle; revisit P-8 if the tool starts printing time-only resets.
- A window whose real reset moves by less than 1 h would not re-arm; no tool is known to have windows that short.
