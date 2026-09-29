---
type: decision
status: accepted
updated: 2026-09-29
aliases: [ADR-020]
tags: [github, errors]
tracks: [Packages/ContribusageKit/Sources/ContribusageGitHub/GitHubClient.swift]
---
# ADR-020: GitHub rate limits are detected by `x-ratelimit-remaining: 0` on a failed response

- **Decided:** 2026-09-29 · **Spec:** SPEC §8.4.3, §13, T-3.3 · **Supersedes:** —

## Context
SPEC §8.4.3 said "when remaining is 0 or a 403/429 arrives, pause until the reset time". GitHub's GraphQL documentation (SPEC §20) says otherwise: an exhausted primary limit answers HTTP 200 with an error and `x-ratelimit-remaining: 0`; a secondary limit answers 200 or 403 with an error, sometimes `retry-after`, and asks for at least one minute's wait when neither header applies. A 403/429 rule alone misses the primary case, and pausing on every 403 would hold secondary limits until the hourly reset.

## Options
| Option | For | Against |
|---|---|---|
| 403/429 means rate limited (old text) | Matches REST habits | Misses the primary GraphQL case entirely; a 403 without budget info has no reset time |
| Remaining 0 on any response pauses | One header check | Discards a successful calendar that spent the last point |
| Remaining 0 on a failed response pauses; other failures go to backoff | Covers both documented primary shapes; keeps good data; no clock in the client | `retry-after` is ignored; the backoff (≥ 1 h for GitHub, SPEC §12) waits longer than needed |

## Decision
`GitHubClient` returns `data` whenever the response is 2xx with `data` and no `errors`. Otherwise it settles the failure (`decoding(message)` for a 2xx, `http(status:)` for the rest), and `x-ratelimit-remaining: 0` with a numeric `x-ratelimit-reset` replaces it with `SourceError.rateLimited(until:)`; failures with budget left fall under the backoff.

## Consequences
- A success that spends the last point is shown; the next fetch fails cheaply with remaining 0 and pauses until the reset.
- Secondary limits wait for the backoff, not for `retry-after`; add `retry-after` if the backoff ever proves too slow.
