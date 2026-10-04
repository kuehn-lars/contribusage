---
type: decision
status: accepted
updated: 2026-10-04
aliases: [ADR-039]
tags: [scheduling, claude-code]
tracks: []
---
# ADR-039: Claude Code probe every minute on request, every 5 minutes by default

- **Decided:** 2026-10-04 · **Spec:** SPEC NFR-5, §8.1.4, §8.1.5, §12 rule 10, §11.6, T-5.21 · **Revised:** 2026-10-04 after R-1 · **Supersedes:** the 15 min default of [[decisions/0002-usage-probe-primary-limits-source]]

## Context
The probe ran every 15 min by default and at most every 5 min, conservative because R-1 (does a probe cost plan quota) is open. In use, limits that are 15 or even 5 minutes old are too late to act on while working close to a limit. The probe is the tool's own CLI on this Mac; it is not an API the app calls, so no service rate limit applies.

## Options
- Lower only the minimum to 1 min, default 15 or 5 min.
- Default and minimum 1 min (the first decision, revised after [[research/r-1-probe-cost]]).

## Decision
Minimum 1 min, default 5 min, maximum 60 min (NFR-5). A probe costs no plan quota, but about 1.7 s of CPU in the `claude` process ([[research/r-1-probe-cost]]): every minute is about 2.7 % of a core while awake, too much for a default, fine as a choice. The rule generalises to section 12 rule 10: a polled source that runs the tool's own CLI or reads local files may run every minute; network APIs keep their service's budget (GitHub, NFR-6).

## Consequences
- 12 `claude` processes per hour by default, 60 at the minimum. With the probe every minute the app itself stays at 0.08 % CPU (NFR-1, [[research/r-1-probe-cost]]); the T-5.8 figures assumed 15 min ([[research/t-5-8-performance-energy]]).
- Settings offers 1, 2, 5, 10, 15, 30 and 60 min. A stored interval is kept, so existing installs keep theirs.
- Low Power Mode doubles the interval (10 min by default, 2 min at the minimum); backoff, single flight (NFR-18) and the 30 s manual floor are unchanged.
