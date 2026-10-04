---
type: decision
status: accepted
updated: 2026-10-04
aliases: [ADR-014]
tags: [build, ci, architecture]
---
# ADR-014: Build and CI foundation

- **Decided:** 2026-09-28 · **Spec:** SPEC §15.2 to §15.6, §16.1, NFR-11, NFR-16, NFR-17, T-1.1 to T-1.3, T-6.8 · **Supersedes:** —

## Context
Phase 1 creates the Xcode project, the package and the lint setup. Three checks guard the architecture from the first commit: zero warnings (NFR-11), an arm64-only executable (NFR-16) and a core that imports no provider or GitHub code (NFR-17). SPEC §15 sketched the setup before any of it was built.

## Options
| Question | Chosen | Rejected, and why |
|---|---|---|
| Project file | Hand-kept `project.pbxproj` with a synchronised `App/` folder and a generated Info.plist | XcodeGen or Tuist: a new tool for one target. Per-file references: every new view edits the project file and invites merge conflicts |
| Zero warnings in the package | `-Xswiftc -warnings-as-errors` in the one package test command that AGENTS.md, SPEC §15.6 and CI all use | `treatAllWarnings(as: .error)` in `Package.swift`: Xcode 26 adds `-suppress-warnings` to package targets it builds for the app, and the compiler rejects the pair, so the app build fails (observed on the `macos-26` runner with Xcode 26.6; Xcode 27 no longer suppresses local packages). A flag passed only in CI: local runs would pass what CI rejects |
| NFR-17 check | `ArchitectureTests` in `ContribusageCoreTests` scans every target's imports | A CI-only grep script: not part of the agent's `swift test` loop. `Package.swift` alone: an undeclared import of an already-built module compiles (observed with `@testable import ContribusageGitHub` in the core) |
| CI shape | One workflow, three parallel jobs on `macos-26` (Apple Silicon): package tests and `swift format --strict`, Release build with `lipo` and `LSMinimumSystemVersion` checks, wiki lint and its regression test | Separate workflows per concern; an Ubuntu wiki job (the hooks run the tooling on macOS, so CI does too) |

## Decision
Build as in the table. CI runs on pull requests and on pushes to `main`, with read-only permissions and superseded runs cancelled.

## Consequences
- Warnings in package code fail `swift test` only with the flag; the app build shows them without failing. Revisit `treatAllWarnings` once CI and the minimum Xcode (SPEC §15.1) are 27 or later.
- `xcodebuild` needs a full Xcode selected (`xcode-select -p` points into `Xcode.app`, or `DEVELOPER_DIR` is set); the Command Line Tools alone build the package but not the app.
- The `Contribusage` scheme is created automatically by `xcodebuild`; a shared scheme file is added when a scheme setting has to differ from the default (archiving in T-6.7).
- The `release` job (2026-10-04) runs on pushes to `main` after the three jobs pass, on `macos-26`: Debug and Release must share one `MARKETING_VERSION` of digits and dots; only when the release `v<version>` is missing does it build the Release app, pack it with an Applications link into `contribusage-<version>.dmg` (`hdiutil`, three tries against the runners' "Resource busy" failures) and attest the DMG's build provenance (`actions/attest`, signed through Sigstore and stored with GitHub, checked with `gh attestation verify`) and create the release at the pushed commit with generated notes and the DMG. Attesting comes before the release, so a failed attestation leaves the version to the next push. Only this job may write (`contents: write`, `id-token: write`, `attestations: write`; `artifact-metadata` is only needed for registry images), and only its two `gh` steps see the token, not the build. Runs on `main` queue instead of cancelling each other, since a release job cancelled between `gh release create`'s draft and its publish would leave a draft that `gh release view` finds, blocking the version.
- Left out until a task needs them: the NFR-15 coverage gate (with the first parsing code, T-2.1), fixture resources (with the first fixture), notarization (T-6.7), live smoke tests (never in CI, SPEC §16.1), dependency update bots (no dependencies yet).
