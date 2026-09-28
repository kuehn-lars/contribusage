---
type: index
updated: 2026-09-28
---
# Index

Every page in the vault, one line each. Read this first to pick the pages a task needs; every new page gets a line here (lint checks it). The contract lives outside the vault in `SPEC.md`: cite it by section or ID (`SPEC §8.1.3`, `FR-8`).

## Start here
- [[overview]]: what contribusage is, how spec, vault and AGENTS.md divide the work, the targets at a glance
- [[log]]: chronological record of changes to the project

## Architecture
- [[architecture/repo-map]]: annotated tree of the repository and the vault (lint-checked)

## Modules
- [[modules/app]]: SwiftUI shell; views and wiring only
- [[modules/core]]: provider-neutral models, scheduler, persistence, support seams
- [[modules/claude-code]]: the v1 provider; `/usage` probe, status line bridge, transcripts
- [[modules/github]]: GraphQL client, token validation, contribution statistics
- [[modules/test-support]]: fakes, `FakeProvider`, provider conformance suite

## Decisions
- [[decisions/0001-native-swift-swiftui]]: ADR-001, Swift and SwiftUI with `MenuBarExtra`
- [[decisions/0002-usage-probe-primary-limits-source]]: ADR-002, `/usage` probe first, status line bridge optional
- [[decisions/0003-official-interfaces-only]]: ADR-003, no credentials, no undocumented vendor endpoints
- [[decisions/0004-logic-in-contribusagekit-package]]: ADR-004, all logic in the local Swift package
- [[decisions/0005-json-file-persistence]]: ADR-005, versioned atomic JSON files
- [[decisions/0006-no-app-sandbox]]: ADR-006, no sandbox, notarized download
- [[decisions/0007-native-transcript-parsing]]: ADR-007, native transcript parser, `ccusage` for validation
- [[decisions/0008-minimum-macos-14]]: ADR-008, macOS 14 minimum
- [[decisions/0009-apple-silicon-only]]: ADR-009, arm64 only
- [[decisions/0010-provider-abstraction-from-day-one]]: ADR-010, provider-neutral core, one target per provider
- [[decisions/0011-product-name-contribusage]]: ADR-011, the name
- [[decisions/0012-llm-wiki-as-project-memory]]: ADR-012, this vault as agent memory, sessions local
- [[decisions/0013-spec-standalone-contract]]: ADR-013, SPEC.md stays the contract; overlaps moved to one owner
- [[decisions/0014-build-and-ci-foundation]]: ADR-014, project file, zero warnings, NFR-17 as a test, CI jobs
- [[decisions/0015-app-paths-struct]]: ADR-015, `AppPaths` is a struct with a root, not a seam
- [[decisions/0016-activity-source-stream-lifetime]]: ADR-016, `ActivitySource` watches while its `reports()` stream is consumed
- [[decisions/0017-unsupported-plan-source-error]]: ADR-017, `SourceError.unsupportedPlan` carries P-10 out of `fetch()`

## Research
- [[research/r-2-usage-output-variants]]: R-2, `/usage` without a subscription: logged out and API key billing print the same cost summary

## Guides
- [[guides/llm-wiki-tooling]]: `wiki.sh`, Claude Code hooks, lint findings, reuse in another repository

## Sources
- [[sources/karpathy-llm-wiki]]: the LLM-wiki pattern this vault implements
