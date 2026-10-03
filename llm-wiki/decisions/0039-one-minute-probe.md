---
type: decision
status: accepted
updated: 2026-10-04
aliases: [ADR-039]
tags: [scheduling, claude-code]
tracks: []
---
# ADR-039: Claude Code probe every minute

- **Decided:** 2026-10-04 · **Spec:** SPEC NFR-5, §8.1.4, §8.1.5, §12 rule 10, §11.6, T-5.21 · **Supersedes:** the 15 min default of [[decisions/0002-usage-probe-primary-limits-source]]

## Context
The probe ran every 15 min by default and at most every 5 min, conservative because R-1 (does a probe cost plan quota) is open. In use, limits that are 15 or even 5 minutes old are too late to act on while working close to a limit. The probe is the tool's own CLI on this Mac; it is not an API the app calls, so no service rate limit applies.

## Options
- Lower only the minimum to 1 min, default 15 or 5 min.
- Default and minimum 1 min.

## Decision
Default and minimum 1 min, maximum 60 min (NFR-5). The rule generalises to section 12 rule 10: a polled source that runs the tool's own CLI or reads local files may run every minute; network APIs keep their service's budget (GitHub, NFR-6).

## Consequences
- About 60 `claude` processes per hour while awake and online. NFR-1 already allows a timer once a minute; NFR-1 and energy are re-measured in T-5.21 (the T-5.8 figures assumed 15 min, [[research/t-5-8-performance-energy]]).
- R-1 is answered in T-5.21 before the default ships; if a probe costs quota, the default goes back up and this ADR is revised.
- Low Power Mode doubles the interval to 2 min; backoff, single flight (NFR-18) and the 30 s manual floor are unchanged.
