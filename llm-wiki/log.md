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

## [2026-09-29] feat | T-2.4 live process runner
- `LiveProcessRunner` in `ContribusageCore/Support/Live`: concurrent pipe reads, SIGTERM then SIGKILL on timeout or cancellation, stdin `/dev/null`
- One process at a time across all runner instances (NFR-18) through a shared FIFO gate; nine process tests against system tools
- Review pass before commit: stopping asks `Process` itself (`isRunning`, `terminate()`) instead of a lock-guarded mirror of its state; the timeout verdict is the deadline task's result

## [2026-09-29] feat | T-2.5 Claude Code provider
- `ClaudeCodeProvider` with descriptor, detection and the `UsageProbe` limits source: cached locate with re-resolution, single flight join, SPEC §13 error mapping; passes the conformance suite
- `SourceError.unsupportedPlan(note:)` added to the core for P-10 ([[decisions/0017-unsupported-plan-source-error]])

## [2026-09-29] refactor | T-2.5 review pass
- `UsageProbe` folded into `ClaudeCodeProvider`, now one actor that is its own `LimitsSource`; the launch retry is a two-pass loop
- Detection no longer reports `unsupportedPlan` from a cached probe note, which the registry could never read; P-10 and ADR-017 updated
- Second pass: the login check also matches "logged in" (whole words only); tests for an override change and each probe result mapping

## [2026-09-29] feat | T-2.6 refresh coordinator
- `Schedule.nextRun` (pure: bounds, backoff, Low Power Mode, offline, sleep, wake delay, manual floor) and `RefreshCoordinator` (serialized passes in registry order, SPEC §13 mapping, `state.json` persistence and restore)
- `SchedulePolicy.needsNetwork` and `Origin.poll` added; ADR-018 settles the coordinator shape and the GitHub seam
- App wiring and the popover/reset triggers moved into T-2.7

## [2026-09-29] refactor | T-2.6 review pass
- `RefreshCoordinator.refresh` separates the SPEC §13 mapping (a pure function) from bookkeeping; failures derive from the state
- `ProviderID` is `CodingKeyRepresentable`, so `state.json` keys need no conversion; one `Duration.timeInterval` replaces three conversions
- Third pass: `restore()` no longer relabels an in-memory snapshot as `cache` when `start()` runs again; the backoff drops a redundant branch

## [2026-09-29] feat | T-2.7 limits UI and app wiring
- The app runs live: `AppState.live()` registers `ClaudeCodeProvider`, starts `RefreshCoordinator` and feeds it sleep, wake, network and Low Power Mode through `SystemConditions`; Refresh, Retry and popover open reach the coordinator.
- Extra triggers as `Schedule.nextRun(trigger:)`: popover open and a window's reset, floored at the minimum interval (SPEC §12 rule 8, [[decisions/0019-extra-refresh-triggers]]).
- Limits section: §11.5 reset wording with hover date, "reset, refreshing…" after a reset (FR-11), §11.7 VoiceOver labels, §13 error wording.
- Fix: provider groups were invisible in the live popover (`ViewThatFits` fell back to a zero-height `ScrollView`); the scroll view now takes the groups' measured height.

## [2026-09-29] refactor | T-2.7 review pass
- `Schedule.nextRun(triggers:)` filters triggers by the last run itself; `popoverOpened()` hands `now` to its one pass instead of storing and clearing it per record ([[decisions/0019-extra-refresh-triggers]]).
- The §11.5 and FR-11 window texts moved from `LimitsSection` into the core (`UsageWindow+Display`) with tests, ready for the menu bar label (T-2.8).
- Retry is an optional closure per section (limits only for now); condition changes reach the coordinator in order through one stream.

## [2026-09-29] refactor | SystemConditions keeps no observer tokens
- `NotificationCenter` holds each block until it is removed, and `SystemConditions` lives as long as the app, so the stored token array is gone.

## [2026-09-29] spec | Menu bar label moves to M4
- T-2.8 becomes T-5.10: the menu bar label (FR-12, SPEC §11.1) follows the GitHub wiring and the display mode setting; M1 is now "limits live in the popover".
- FR-12 drops to P2; US-1 notes that its menu bar criteria arrive with T-5.10, and the M1 check covers only its popover criteria.

## [2026-09-29] fix | Probe folder created owner-only
- The first probe created `~/Library/Application Support/contribusage/` with the default `0755` before `JSONStore` could create it as `0700` (SPEC §10.7). Found during the M1 check.
- `JSONStore.createFolder` is now the one place that creates folders under the root; `JSONStore.write` and the probe both use it, and `createsTheProbeFolderOwnerOnly` covers the probe path.

## [2026-09-29] test | M1 check
- US-1's popover criteria and US-2 hold over a day of uptime without sleep; SPEC §17.2's M1 check is ticked.
- Release build sampled once a minute (`ps` CPU time, `footprint`): quiet minutes cost at most 0.01 s CPU (NFR-1), memory footprint 15 to 25 MB (NFR-2). Opening the popover adds about 8 MB and 0.5 s; a probe about 0.3 s.

## [2026-09-29] feat | T-3.1 KeychainSecretStore
- `KeychainSecretStore(service:)` in the core's `Support/Live` is the live `SecretStore`: generic passwords, key as account, after first unlock and this device only (FR-16, SPEC §14).
- `keychainSecretStoreRoundTrips` runs against the real Keychain under a throwaway service only with `CONTRIBUSAGE_LIVE_TESTS=1`; `FakeSecretStore` keeps its unit test.

## [2026-09-29] feat | T-3.2 GitHub settings tab
- `GitHubClient.viewerLogin(token:)` validates a token with `viewer { login }` (FR-17); fake-transport tests cover the request, 401, HTTP errors and GraphQL errors.
- `GitHubAccount` owns the token: only a validated token is saved, tested with fakes. New Settings scene with the GitHub tab (validate, "Connected as @login", remove); Connect GitHub in the popover opens it.
- `SourceError.message(displayName:)` is shared by popover and Settings; `unauthorized` now reads "GitHub token is invalid or expired" (SPEC §13). SPEC §10.7 gains the `githubLogin` default; T-3.2 ticked.

## [2026-09-29] feat | T-3.3 GitHubClient contributions
- `GitHubClient.contributions(token:from:to:)` returns a `ContributionCalendar`, which `GitHubReport` now carries with the stats (SPEC §10.5); one generic `send` serves it and `viewerLogin`. The query drops the unused `weekday` (Appendix C).
- Rate limits follow GitHub's GraphQL docs: remaining 0 on a failed response pauses until the reset; SPEC §8.4.3 and §13 corrected ([[decisions/0020-github-rate-limit-detection]]).
- Fixtures `github/calendar.json` and `github/graphql-errors.json`, both synthetic; SPEC §16.2 no longer asks for a real calendar, whose counts are personal data.

## [2026-09-30] feat | T-3.4 contribution statistics
- `ContributionStats(days:now:calendar:)` computes today, this week and both streaks per SPEC §8.4.4, ignoring entries after today.
- ADR-021: the caller's `Calendar` defines today and the week start, so R-4 now blocks T-3.6 instead of T-3.4; SPEC §8.4.4, §17, §19.1 updated.

## [2026-09-30] feat | T-3.6 GitHub in the refresh coordinator
- `RefreshCoordinator<GitHubValue>` runs an app-supplied `GitHubJob` in its passes, persists it under `github` in `state.json`; no token and 401 wait for the user, a rate limit runs at its reset, a token change resets inside a pass (ADR-022).
- `GitHubAccount.report(now:calendar:)` fetches the year and its statistics; the app wires it with `Calendar.current` until R-4, Settings reports token changes, GitHub errors show Retry.

## [2026-09-30] fix | Heatmap fits the popover
- The live 365-day calendar drew 53 columns and widened the popover; the heatmap now draws `ContributionCalendar.weeks(last: 26)` (FR-20 default), Sunday-aligned from the last day, with top-aligned columns.
- Mock and placeholder use real dates, so previews show the same layout as live data.
- Cells are squares sharing the content width, placed by the `WeekColumns` layout, which derives its height from the width: `aspectRatio` cells shrank to dots under the menu bar window's small height proposal.

## [2026-09-30] refactor | One job type in the refresh coordinator
- Providers' limits and GitHub are both a `Job<Value>` run by one generic `run`; no token is `SourceError.tokenMissing`; a token change replaces GitHub's record and persists (ADR-022).
- `ContributionCalendar` keeps GitHub's `weeks` (SPEC §10.5), the heatmap takes `weeks.suffix(26)`; `AppState` owns the GitHub account and tells the coordinator about token changes itself.

## [2026-09-30] feat | Change token… after a 401, fixed heatmap range, M2 done
- FR-20, US-4, §10.7, §11.6: the heatmap shows 26 weeks with no range setting; `heatmapWeeks` is gone (the 52-week option had no use). Hover tooltips appear after 0.2 s (`NSInitialToolTipDelay`); a heatmap cell's reads "2026-09-27: 5 contributions" (§11.2).
- A 401's error line offers "Change token…" instead of Retry, which opens Settings (US-4, §13, §16.5); the GitHub tab is one Account row (Disconnect) and one token field (Connect, or Replace, which keeps the saved token until the new one validates; §11.6).
- T-3.5 done with hover; its palette, keyboard and VoiceOver work moves to T-5.11 (M4). M2 checked by hand, ticked.

## [2026-10-01] feat | Structured insights area (T-6.1)
- `UsageParser` turns the "What's contributing" block into `Insights` (periods, shares, rankings; unknown lines kept); `state.json` schema 2.
- The popover shows one period at a time with a segmented picker, the top three per ranking and the note as a tooltip.
- SPEC FR-8, FR-38, US-8, P-11, §7.2, §10.3 updated; [[decisions/0023-structured-insights]].

## [2026-10-02] feat | Transcript line decoder (T-4.1)
- `TranscriptLine.decode` reads usage-bearing lines leniently; non-usage lines give nil, malformed ones throw (FR-23, SPEC §8.3.2).
- One `JSONDecoder` and one date format style are built once, since decode runs per line (NFR-7).
- Field paths confirmed against real transcripts; R-3 stays open for the ccusage comparison (T-4.7).

## [2026-10-02] feat | Transcript aggregator (T-4.2)
- `TranscriptAggregator` de-duplicates by `message.id:requestId` and buckets per local day and model (FR-24, FR-25); `TokenCounts` gained `+=`.
- Per-file removal for FR-26 is left to T-4.3.
- Review pass: `DayKey(_:calendar:)` in the core replaces two copies of the day formatting (aggregator, `ContributionStats`); the aggregator's key and token-count code shortened.

## [2026-10-02] feat | Incremental JSONL reader and transcript files (T-4.3)
- Core `IncrementalJSONLReader` returns appended complete lines per file and flags a rescan on identity change or shrink; a deleted file reads as `nil` (FR-26, SPEC §8.3.5).
- Claude Code `TranscriptFiles` lists FR-22 roots and `**/*.jsonl`, skipping the probe folder's project directory (FR-28).
- SPEC §8.3.1: project directories encode every non-alphanumeric character as `-`, not only `/`.

## [2026-10-02] feat | History store (T-4.4)
- Core `HistoryStore` keeps a provider's frozen days in `providers/<id>/history.json`: a day freezes once it ended more than 48 h ago, is never recomputed, and is kept 365 days (FR-29, SPEC §8.3.4).
- `merge(_:now:calendar:)` freezes, prunes, writes only on change and returns frozen days plus unfrozen live days younger than 48 h, each day once; an unreadable file throws and stays on disk.
- Test support: `AppPaths.temporary()` replaces three private copies of the temporary root helper.

## [2026-10-02] feat | Live file events with FSEvents (T-4.5)
- Core `FSEventsFileEvents`: one FSEvents stream per consumer, file level events, the debounce as latency, utility queue (FR-27).
- Batches report files only, by real path; a root created later is picked up; dropped events are left to the activity source's rescan.; a stream that cannot start finishes.

## [2026-10-02] feat | Claude Code activity source and Activity section (T-4.6)
- `TranscriptActivity`: roots from FR-22 plus the login shell's `CLAUDE_CONFIG_DIR`, a full incremental pass per file event or rescan, de-duplicated across files, merged with the history store; `ClaudeCodeProvider` gains the `activity` capability and passes the conformance suite with it.
- App: one `reports()` consumer per enabled provider, rescans on popover open and wake, `noLocalData` when no days exist; `ActivitySection` shows today by date, the reported token categories only and a zero-filled 7 day chart with a VoiceOver summary.
- ADR-024: the live index stays in memory; T-4.7 decides on persisting it. ADR-025: the SPEC §16.4 declared-roots read check and its file system seam move to T-4.7. `TranscriptFiles.roots` now returns missing roots too, so they are watched.

## [2026-10-02] spec | ccusage validation recorded (T-4.7)
- SPEC §8.3.6 and R-3: daily token totals match `ccusage daily` within 1 %, checked by hand against the built activity source.

## [2026-10-02] fix | Live index within NFR-2, NFR-7 measured (T-4.7)
- Opt-in performance test over a generated 520 MB tree: cold scan 1.5–1.7 s, incremental 42 ms in release on an M3; NFR-7 judged on the M3 against half its budget (ADR-026). The live index stays in memory (ADR-024), `live-index.json` left SPEC §10.7.
- Memory went from about 400 MB growth to 27 MB: the JSONL reader streams through a fixed buffer instead of autoreleased whole-file data, and the live index keeps the first line per key (SPEC §8.3.4). Findings: [[research/nfr-7-transcript-scan]].

## [2026-10-02] test | Declared-roots read check (T-4.7)
- New seam `FileReading` (SPEC §10.6): the transcript listing, the JSONL reader and the history store read through it; `LiveFileReader` in the app.
- `ProviderConformance` fails a provider that lists or reads outside its declared roots (SPEC §16.4, ADR-025), proven by `conformanceSuiteRejectsAReadOutsideTheRoots` and a mutation run.

## [2026-10-02] fix | T-4.7 review fixes
- Interning survives incremental appends; the reader returns a named `Outcome`; `JSONStore.read` takes its `FileReading` without a default.
- The read check fails when nothing went through the seam and resolves symlinks; the perf test asserts ADR-026's half budget and fails if it cannot measure memory. T-4.7 ticked.
