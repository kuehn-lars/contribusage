---
type: module
status: active
updated: 2026-09-29
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
`GitHubReport.swift` holds the SPEC §10.5 types (`ContributionLevel`, `ContributionDay`, `ContributionStats`, `ContributionCalendar`, `GitHubReport`), added for the popover shell (T-1.7), plus `GitHubReport.staleAfter` (2 h, SPEC §12). `GitHubReport` is the fetched `calendar` plus the computed `stats`, so the client's result is carried whole rather than copied field by field. Built so far: `gitHubGraphQLEndpoint`, the app's only network destination (NFR-13), pinned by a test. `GitHubClient(transport:version:)` sends GraphQL through `HTTPTransport` with `Authorization: Bearer`, `User-Agent: contribusage/<version>` (SPEC §8.4.1); every query goes through one private `send`, which returns the `data` of a 2xx response without `errors` and maps the rest (SPEC §8.4.3): 401 → `SourceError.unauthorized`; otherwise it settles the failure first (a 2xx with `errors` → `.decoding(first message)`, other non-2xx → `.http(status:)`) and then lets `x-ratelimit-remaining: 0` override it with `.rateLimited(until: x-ratelimit-reset)` ([[decisions/0020-github-rate-limit-detection]]). `viewerLogin(token:)` (FR-17, T-3.2) returns the login. `contributions(token:from:to:)` (FR-18, T-3.3) sends the Appendix C query with `from`/`to` as ISO 8601 with the local offset and returns a `ContributionCalendar` (login, days in API order, `totalContributions`); levels map by their position in Appendix C's name list, and an unknown `contributionLevel` is a `.decoding` error, so a changed enum shows up instead of drawing as empty. The caller computes `from` and `to` and turns the calendar into a `GitHubReport` with the T-3.4 statistics. `GitHubAccount(secrets:client:)` owns the saved token (FR-16, key `token`): `connect(token:)` validates first and saves only an accepted token (SPEC §14), `disconnect()` deletes it; both are `async`, so their Keychain calls leave the caller's actor.

## Tests
`GitHubClientTests` loads `Fixtures/github/` (SPEC §16.2): `calendar.json` is synthetic in the shape of a real 365-day response to the Appendix C query (login `octocat`, 53 weeks with a partial first week starting on a Tuesday, all five levels, total 1917), since real counts are personal data; the unknown-level test renames `NONE` in it. `graphql-errors.json` is a synthetic `RATE_LIMITED` error that `sendMapsFailures` pairs with each status and remaining budget: remaining 0 → `rateLimited`, budget left → `decoding` or `http`. The calendar test also pins the local offset in `from` (not `Z` unless the machine runs on UTC) and the level order (levels rise with the count, so a swapped name in `levelNames` fails). `restrictedContributionsCount` is in the query (Appendix C) but not decoded until R-4 settles its meaning.

## Related
[[modules/app]] (heatmap and GitHub settings tab)
