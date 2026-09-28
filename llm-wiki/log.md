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

## [2026-09-28] fix | App build on Xcode 26: zero warnings via the test command
- CI's Release build failed: Xcode 26.6 passes `-suppress-warnings` to package targets, which conflicts with `treatAllWarnings(as: .error)` from `Package.swift`.
- The package now enforces zero warnings through `swift test ... -Xswiftc -warnings-as-errors` (AGENTS.md, SPEC §15.6, CI); tools version back to 6.1 ([[decisions/0014-build-and-ci-foundation]]).

## [2026-09-28] spec | T-1.1 and T-6.8 done
- T-1.1: the app launches as a menu bar agent (icon, no Dock icon, Quit) and the Release build is arm64 only.
- T-6.8: the CI workflow's first fully green run on a pull request ([[decisions/0014-build-and-ci-foundation]]).

## [2026-09-28] feat | T-1.4 support seams and fakes
- `ContribusageCore/Support`: the SPEC §10.6 protocols, live `SystemTimeSource` and `URLSessionTransport`; `AppPaths` is a struct with a root ([[decisions/0015-app-paths-struct]]).
- `ContribusageTestSupport/Fakes.swift`: a fake per protocol, each used in `SupportTests`; the live process runner, Keychain store and FSEvents watcher stay with T-2.4, T-3.1 and T-4.5 ([[modules/core]], [[modules/test-support]]).

## [2026-09-28] feat | T-1.5 persistence
- `JSONStore` (core, `Persistence/`): versioned atomic JSON files, folders created `0700`, version mismatch throws and never deletes; `AppPaths.deleteProviderData` for US-12.
- Files are the envelope `{"schemaVersion", "value"}`; SPEC §10.7 says so and exempts the bridge's `statusline-limits.json`.
- SPEC Appendix D: the bridge creates its folders under `umask 077`, so the root stays `0700` whoever creates it first.

## [2026-09-28] feat | T-1.6 provider framework
- Core `Providers/`: descriptor, capabilities, availability, `UsageProvider`, `LimitsSource`, `ActivitySource`, the neutral reports and `SourceError`; `ProviderRegistry` with order, first-run enablement and availability caching ([[modules/core]]).
- Test support: `FakeProvider` and `ProviderConformance`; the fake passes the suite, and a broken provider is shown to fail it ([[modules/test-support]]).
- [[decisions/0016-activity-source-stream-lifetime]]: `ActivitySource` drops `start`/`stop`; SPEC §10.2 and §16.4 follow.

## [2026-09-28] feat | T-1.7 popover shell
- Core gains `Snapshot`, `Origin`, `SourceState`, `NotConfiguredReason` (SPEC §10.1); GitHub gains the §10.5 report types.
- App: `AppState`, popover views drawing every SPEC §11.3 state, mock data and one light/dark preview per state, one and two providers.

## [2026-09-28] feat | T-2.1 usage parser
- `UsageParser` in `ContribusageClaudeCode/Limits/` implements SPEC §8.1.3 P-1 to P-9 and the §8.1.4 classification, returning core `UsageWindow`s; written from the rules because no earlier parser existed in the repository.
- Swift Testing tests with the Appendix A fixture via `Bundle.module`, covering every P-7 format, year rollover, the Berlin DST change, New Year and the unknown zone fallback.
- Review pass: the parser returns core `UsageWindow` instead of its own window type, P-7 formats carry an explicit `dated` flag, and an unused test constant is gone.

## [2026-09-29] research | R-2 usage output variants
- Logged out and API key billing both exit 0 with the same cost summary and no windows; captured as fixtures ([[research/r-2-usage-output-variants]]).
- SPEC P-10 and §13 name the exact text; logged out lands in `unsupportedPlan`.

## [2026-09-29] feat | T-2.2 limits report
- `UsageParser.report` returns the `LimitsReport` with `billingNote`, `insights` and `rawOutput` (SPEC §8.1.3 P-10, P-11); it is the parser's only public entry point; `windows(in:)` is gone, a private `window(in:)` reads one line.
- SPEC §16.2 synthetic fixtures stay inline strings in the tests.

## [2026-09-29] feat | T-2.3 Claude locator
- `ClaudeLocator` resolves `claude` in FR-6 order over `ProcessRunning` and returns the login shell's PATH with it, so npm installs validate from a Finder-started app
- Stateless by design: caching moved to the provider task T-2.5, which owns re-resolution
- `executableKind(at:)` tells arm64, x86_64 and script apart from the file header (FR-36)

## [2026-09-29] refactor | T-2.3 review pass
- `ClaudeLocator.ExecutableKind(at:)` reads header words with `UInt32(bigEndian:)`/`UInt32(littleEndian:)` instead of reversing bytes by hand
- Dropped `Equatable` from `Found` (never compared) and the explicit one on `ExecutableKind` (enums without payloads get it)
