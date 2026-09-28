---
type: module
status: active
updated: 2026-09-29
tracks: [Packages/ContribusageKit/Sources/ContribusageClaudeCode, Packages/ContribusageKit/Tests/ContribusageClaudeCodeTests]
tags: [provider, claude-code]
---
# ContribusageClaudeCode

The v1 provider (`claude-code`). Limits come from the `/usage` probe (locator, probe, parser, window classifier) and the optional status line bridge; activity comes from local transcripts (decoder, aggregation keys, roots). It never touches Claude Code's credentials and never uses the network ([[decisions/0003-official-interfaces-only]]).

## Spec
- **Sections:** SPEC §2.1 (compliance note), §8.1 to §8.3 (probe, bridge, transcripts), §16.6 (update procedure), Appendices A, D, E
- **Requirements:** FR-6 to FR-11, FR-22 to FR-28, FR-38, FR-39, FR-41
- **Research:** R-1 (probe cost), R-2 (output variants), R-3 (transcripts), R-5 (probe performance)
- **Tasks:** T-2.1 to T-2.5, T-4.1, T-4.2, T-4.6, T-6.1 to T-6.3, T-6.6
- **Path:** `Packages/ContribusageKit/Sources/ContribusageClaudeCode/`; bridge script `scripts/contribusage-statusline.sh`

## Depends on
[[modules/core]] only.

## Contract
Built so far: `ProviderID.claudeCode` (`claude-code`), pinned by a test because persistence folders and settings keys derive from it (SPEC §10.7).

`UsageParser.report(from:now:fallbackZone:)` (`Limits/UsageParser.swift`) is the parser's one entry point: it strips ANSI codes and splits lines once, then builds the `LimitsReport` for `claude-code` with core `UsageWindow`s classified by label (SPEC §8.1.3, §8.1.4). It is pure: `now` and the fallback zone are parameters, so tests pin both. Classification is a private function tested through the parser (`classifiesWindow`); it lives here rather than in a separate `WindowClassifier` because it is three lines and has no other caller.

Beyond the windows, `billingNote` is the first non-empty line, `insights` everything from the "What's contributing" line to the end, `rawOutput` the output as received, ANSI codes included (P-10, P-11). Deciding `unsupportedPlan` from the note is left to the provider (T-2.5). The synthetic cases of SPEC §16.2 (model window, unknown window, `<1%`, ANSI) are inline strings in the tests, not fixture files.

`ClaudeLocator` (`Limits/ClaudeLocator.swift`, FR-6) is a stateless struct over `ProcessRunning`. `locate(override:)` runs the login shell once (`command -v claude`, then `$PATH` as the last line), then tries the override, the shell's answer and the four known locations in that order, and returns the first whose `--version` exits 0 within 10 s, with its version and the environment it passed: the app's environment with the login shell's PATH (SPEC §8.1.1). The probe reuses that environment. Caching lives in the provider (T-2.5), which is the only place that sees when the path stops working and also throttles re-resolution after a miss (SPEC §13); keeping hits and misses in one owner is why the locator holds no state. An invalid override falls through to the other candidates; SPEC FR-6 leaves this open. `ClaudeLocator.ExecutableKind(at:)` reads the first 512 bytes for FR-36: thin Mach-O arm64 or x86_64, universal (arm64 when it has an arm64 slice), `#!` script, otherwise unknown.

## Things that bite
- `Fixtures/usage/subscription-basic.txt` is reconstructed from Appendix A, not yet captured byte for byte as SPEC §16.2 requires; recapture it with the SPEC §16.6 command.
- Reset times resolve through `Calendar` in the clause's zone, so the Berlin DST change and New Year come out right; time only resets use `nextDate(after:)`, which already skips past `now`.
- Logged out and API key billing print the same bytes and exit 0 ([[research/r-2-usage-output-variants]]); the parser cannot tell them apart, and neither can the provider.
- The login shell answer counts only when it is an absolute path: for an alias `command -v` prints `alias claude=…`.
- A Finder-started app inherits launchd's PATH (`/usr/bin:/bin:/usr/sbin:/sbin`). An npm install is a `#!/usr/bin/env node` script, so `--version` fails without the login shell's PATH when `node` sits in `/opt/homebrew/bin`; hence the PATH is applied to validation, not only to the probe.
- Profile scripts may print to stdout, so the shell prints PATH last and the locator reads from the end.
- `DateFormatter` needs the `am`/`pm` suffix split off and upper-cased (`4:09am` → `4:09 AM`) before the P-7 formats match.

## Related
[[decisions/0002-usage-probe-primary-limits-source]] · [[decisions/0007-native-transcript-parsing]]
