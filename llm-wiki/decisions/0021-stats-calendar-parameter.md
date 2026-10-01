---
type: decision
status: accepted
updated: 2026-10-02
aliases: [ADR-021]
tags: [github, time]
tracks: [Packages/ContribusageKit/Sources/ContribusageGitHub/GitHubReport.swift]
---
# ADR-021: Contribution statistics take the `Calendar` that defines today

- **Decided:** 2026-09-30 · **Spec:** SPEC §8.4.4, FR-19, T-3.4, T-3.6, R-4 · **Supersedes:** —

## Context
T-3.4 depended on R-4, which asks which time zone GitHub uses for a calendar day. The answer only changes which date counts as today and where the week starts; the streak and sum rules do not change.

## Options
| Option | For | Against |
|---|---|---|
| Wait for R-4 | Nothing built on a guess | Blocks pure, testable logic on a manual midnight comparison |
| Hard-code the local zone | Simplest call | R-4 may pick another zone, and then the calculator changes |
| Take a `Calendar` | Its time zone sets the day boundary, its first weekday the week start; R-4 only picks what the caller passes | One more argument |

## Decision
The statistics are a pure initializer, `ContributionStats(days:now:calendar:)`, rather than the `ContributionStatsCalculator` type SPEC §9 first named: a namespace around one function adds a name and no behaviour. Today's `DayKey` is `now` in `calendar.timeZone`, and the week starts at `calendar.dateInterval(of: .weekOfYear, for: now)`. Entries after today count toward no statistic, so a GitHub day boundary ahead of the calendar's shows no future day.

## Consequences
- T-3.4 no longer waits for R-4; T-3.6 passes `Calendar.current` until R-4 names another zone ([[decisions/0022-github-job-in-the-coordinator]]).
- The time zone rule is tested with a fixed instant under two zones.
