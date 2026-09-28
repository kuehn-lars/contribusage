---
type: decision
status: accepted
updated: 2026-09-28
aliases: [ADR-015]
tags: [core, testing, persistence]
tracks: [Packages/ContribusageKit/Sources/ContribusageCore/Support/AppPaths.swift]
---
# ADR-015: `AppPaths` is a struct, not a seam

- **Decided:** 2026-09-28 · **Spec:** SPEC §10.6, §10.7, T-1.4 · **Supersedes:** —

## Context
SPEC §10.6 sketched `AppPaths` as a protocol with a live implementation and a fake, like the other seams. Unlike them it does no I/O: it only derives URLs from one root folder, so a live and a fake adapter would differ in that root alone.

## Options
| Option | For | Against |
|---|---|---|
| Protocol, `LiveAppPaths`, `FakeAppPaths` | Matches the other seams | Two types that differ in one URL; the folder layout would have to be kept identical in both, or live in a protocol extension that no adapter overrides |
| Struct holding the root, `AppPaths.live` | One type, one place for the layout; tests use the real layout under a temporary root | Differs in shape from the other seams |

## Decision
`AppPaths` is a `Sendable` struct with `init(root:)`, `static let live` (`~/Library/Application Support/contribusage/`) and `providerFolder(_:)`. Tests construct it with a temporary folder.

## Consequences
- No fake for `AppPaths` in `ContribusageTestSupport`; T-1.4's "fake for every seam" covers the five protocols.
- Creating the folders with `0700` stays with persistence (T-1.5); `AppPaths` never touches the disk.
- Revisit if path resolution ever needs I/O or per-environment logic (for example a sandbox container), which would make it a seam again.
