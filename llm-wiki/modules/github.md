---
type: module
status: active
updated: 2026-10-04
tracks: [Packages/ContribusageKit/Sources/ContribusageGitHub, Packages/ContribusageKit/Tests/ContribusageGitHubTests]
tags: [github]
---
# ContribusageGitHub

GitHub contributions: the GraphQL client, token validation and contribution statistics (today, week, streaks). GitHub is a separate, always-available source, not a provider. The token is read only through `SecretStore` and never logged.

## Spec
- **Sections:** SPEC §2.2, §8.4 (request, token, rate limits, statistics), §10.5, Appendix C
- **Requirements:** FR-16 to FR-21; NFR-6, NFR-13
- **Research:** R-4 (private contributions, day boundaries)
- **Tasks:** T-3.2 to T-3.6, T-6.5
- **Path:** `Packages/ContribusageKit/Sources/ContribusageGitHub/`

## Depends on
[[modules/core]] only.

## Contract
`GitHubReport.swift` holds the SPEC §10.5 types (`ContributionCalendar` keeps GitHub's `weeks`, Sunday first, and derives `days`) (`ContributionLevel`, `ContributionDay`, `ContributionStats`, `ContributionCalendar`, `GitHubReport`), added for the popover shell (T-1.7), plus `ContributionStats.menuBarMeters(days:now:calendar:)` (today's level and the week's days with contributions for the menu bar's GitHub meters, T-5.22, FR-51) and `GitHubReport.policy`, the SPEC §12 `SchedulePolicy` (30 min / 10 min / 6 h, stale after 2 h, manual floor 30 s, needs the network). `GitHubReport` is the fetched `calendar` plus the computed `stats`, so the client's result is carried whole rather than copied field by field. Built so far: `gitHubGraphQLEndpoint`, the app's only network destination (NFR-13), pinned by a test. `GitHubClient(transport:version:)` sends GraphQL through `HTTPTransport` with `Authorization: Bearer`, `User-Agent: contribusage/<version>` (SPEC §8.4.1); every query goes through one private `send`, which returns the `data` of a 2xx response without `errors` and maps the rest (SPEC §8.4.3): 401 → `SourceError.unauthorized`; otherwise it settles the failure first (a 2xx with `errors` → `.decoding(first message)`, other non-2xx → `.http(status:)`) and then lets `x-ratelimit-remaining: 0` override it with `.rateLimited(until: x-ratelimit-reset)` ([[decisions/0020-github-rate-limit-detection]]). `viewerLogin(token:)` (FR-17, T-3.2) returns the login. `contributions(token:from:to:)` (FR-18, T-3.3) sends the Appendix C query with `from`/`to` as ISO 8601 with the local offset and returns a `ContributionCalendar` (login, weeks as sent, `totalContributions`); levels map by their position in Appendix C's name list, and an unknown `contributionLevel` is a `.decoding` error, so a changed enum shows up instead of drawing as empty. The caller computes `from` and `to` and turns the calendar into a `GitHubReport` with the statistics: `ContributionStats(days:now:calendar:)` (FR-19, T-3.4) is pure and applies SPEC §8.4.4 to the days up to today, where the `calendar`'s time zone defines today and its first weekday the week ([[decisions/0021-stats-calendar-parameter]]). `GitHubAccount(secrets:client:)` owns the saved token (FR-16, key `token`): `connect(token:)` validates first and saves only an accepted token (SPEC §14), `disconnect()` deletes it; both are `async`, so their Keychain calls leave the caller's actor. `report(now:calendar:)` (T-3.6) is the coordinator's GitHub fetch: `SourceError.tokenMissing` without a saved token, otherwise the calendar from the start of `calendar`'s day 364 days ago to `now` (SPEC §8.4.1) with its statistics; the app passes `Calendar.current` until R-4 ([[decisions/0022-github-job-in-the-coordinator]]).

## Tests
`GitHubClientTests` loads `Fixtures/github/` (SPEC §16.2): `calendar.json` is synthetic in the shape of a real 365-day response to the Appendix C query (login `octocat`, 53 weeks with a partial first week starting on a Tuesday, all five levels, total 1917), since real counts are personal data; the unknown-level test renames `NONE` in it. `graphql-errors.json` is a synthetic `RATE_LIMITED` error that `sendMapsFailures` pairs with each status and remaining budget: remaining 0 → `rateLimited`, budget left → `decoding` or `http`. The calendar test also pins the local offset in `from` (not `Z` unless the machine runs on UTC) and the level order (levels rise with the count, so a swapped name in `levelNames` fails). `ContributionStatsTests` builds consecutive days around Wednesday 2026-09-30: the week with Monday and with Sunday first, a trailing entry for tomorrow that counts nowhere, today at 0 or missing (the streak ends yesterday and asks for today), no streak (nothing asked), and one instant under UTC and Asia/Tokyo picking different days. Each rule was mutation-tested. `GitHubAccountTests` also checks `report(now:calendar:)`: `tokenMissing` and no request without a token, and under Asia/Tokyo the range starts at that zone's midnight 364 days back and today is the fixture's last day. The calendar test also pins the week shape (5, then 51 × 7, then 3 days; 26 weeks back starts on a Sunday). `restrictedContributionsCount` is in the query (Appendix C) but not decoded until R-4 settles its meaning.

## Related
[[modules/app]] (heatmap and GitHub settings tab)
