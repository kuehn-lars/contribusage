---
type: log
updated: 2026-09-28
---
# Log

Append-only record of what changed in the project, newest last. Entry format: `## [YYYY-MM-DD] <type> | <title>` with one to three bullets. `grep '^## \[' log.md | tail -5` shows the latest entries.

## [2026-09-28] spec | Specification 0.1
- SPEC.md drafted: provider framework, Claude Code limits and activity, GitHub contributions, tasks in six phases.

## [2026-09-28] wiki | Project memory and agent protocol
- Set up the `llm-wiki/` vault: overview, index, repo map, one page per build target, `wiki.sh` tooling with Claude Code hooks ([[decisions/0012-llm-wiki-as-project-memory]]).
- `AGENTS.md` defines the per-turn protocol and what may be published; `CLAUDE.md` imports it.

## [2026-09-28] decision | Spec and vault overlaps resolved
- ADR-001 to ADR-011 moved from SPEC §18 into `decisions/`; Appendix B replaced by `AGENTS.md` ([[decisions/0013-spec-standalone-contract]]).
- Appendix A's sample output scrubbed of skill and plugin names (SPEC §16.2 rule).

## [2026-09-28] chore | Codebase foundation and CI
- Xcode project (arm64, macOS 14, agent app) and `ContribusageKit` with the SPEC §15.4 targets, one seed type and test each (T-1.2, T-1.3; T-1.1 awaits a visual check).
- `ArchitectureTests` enforces NFR-17 on every `swift test`; CI runs tests, format, the arm64 Release build and the wiki lint ([[decisions/0014-build-and-ci-foundation]]).
- Open design points in SPEC §9/§10 listed on [[modules/core]] and [[modules/app]].

## [2026-09-28] fix | NFR-17 import scan covers attributed imports
- `ArchitectureTests` missed `@_spi(X) import` and access-level imports (`public import`); an `@_spi` import of `ContribusageGitHub` in the core compiled and passed. The pattern now matches both.
- Seed file in `ContribusageTestSupport` renamed to `ProviderID+Fake.swift` after what it holds; README gains build steps.
