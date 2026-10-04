---
type: decision
status: accepted
updated: 2026-10-04
aliases: [ADR-006]
tags: [platform, distribution, security]
---
# ADR-006: No App Sandbox; distribution outside the Mac App Store

- **Decided:** 2026-09-28 · **Spec:** SPEC §1.3, §14, §15.3 · **Supersedes:** —

## Context
The app has to launch tool binaries such as `claude` and read the files those tools write (`~/.claude`).

## Options
| Option | For | Against |
|---|---|---|
| No sandbox, Developer ID signing and notarization | Can run the user's tools and read their files | No Mac App Store |
| Sandbox with security-scoped bookmarks | App Store eligible | Cannot launch arbitrary binaries |

## Decision
App Sandbox off, Hardened Runtime on, distributed as a notarized download.

Amended 2026-10-04: no notarized download for v1.0. The app is a hobby project with ad-hoc signing ("Sign to Run Locally"); Developer ID signing and notarization cost a paid developer account. Each release carries the ad-hoc signed app as an arm64 DMG instead, and the README tells users to remove the quarantine flag once (`xattr -dr com.apple.quarantine`) or to use Open Anyway in System Settings. Signing and notarization (T-6.7) can follow at a later stage, for example once the project draws enough users.

## Consequences
- Without the sandbox, the app's own discipline is the boundary: it runs only resolved executables with argument arrays and reads only declared roots (SPEC §14).
- CI's `release` job builds the DMG and creates the release when the version changes ([[decisions/0014-build-and-ci-foundation]]). Gatekeeper blocks the downloaded app until the user clears the quarantine flag; an app built from source carries no flag. A signed download then needs Developer ID signing and notarization.
