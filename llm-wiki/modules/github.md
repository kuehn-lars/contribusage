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
`GitHubReport.swift` holds the SPEC §10.5 types (`ContributionLevel`, `ContributionDay`, `ContributionStats`, `GitHubReport`), added for the popover shell (T-1.7), plus `GitHubReport.staleAfter` (2 h, SPEC §12). Built so far: `gitHubGraphQLEndpoint`, the app's only network destination (NFR-13), pinned by a test. `GitHubClient(transport:version:)` sends GraphQL through `HTTPTransport` with `Authorization: Bearer`, `User-Agent: contribusage/<version>` (SPEC §8.4.1); `viewerLogin(token:)` (FR-17, T-3.2) returns the login, maps 401 to `SourceError.unauthorized`, other non-2xx to `.http(status:)`, and a 200 with an `errors` array to `.decoding` (SPEC §8.4.3). `GitHubAccount(secrets:client:)` owns the saved token (FR-16, key `token`): `connect(token:)` validates first and saves only an accepted token (SPEC §14), `disconnect()` deletes it; both are `async`, so their Keychain calls leave the caller's actor. The contributions query, rate limit headers and the rest of the error mapping are T-3.3, which should pull the request building and the `data`/`errors` envelope out of `viewerLogin` into one generic send instead of copying it.

## Related
[[modules/app]] (heatmap and GitHub settings tab)
