---
type: module
status: planned
updated: 2026-09-28
tracks: []
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

## Related
[[modules/app]] (heatmap and GitHub settings tab)
