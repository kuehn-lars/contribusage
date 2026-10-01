---
type: module
status: active
updated: 2026-10-02
tracks: [Packages/ContribusageKit/Sources/ContribusageClaudeCode, Packages/ContribusageKit/Tests/ContribusageClaudeCodeTests]
tags: [provider, claude-code]
---
# ContribusageClaudeCode

The v1 provider (`claude-code`). Limits come from the `/usage` probe (locator, probe, parser, window classifier) and the optional status line bridge; activity comes from local transcripts (decoder, aggregation keys, roots). It never touches Claude Code's credentials and never uses the network ([[decisions/0003-official-interfaces-only]]).

`TranscriptLine.decode(_:)` (`Activity/TranscriptLine.swift`, T-4.1, FR-23, SPEC §8.3.2) decodes one JSONL line with a private all-optional `Decodable`: unknown fields are ignored, missing token counts are 0. It returns `nil` for lines that carry no usage (not `assistant`, no `message.usage`, placeholder model such as `<synthetic>`) and throws for non-JSON or a missing or unparseable `timestamp`; the aggregator (T-4.2) counts the throws as malformed lines. Timestamps carry fractional seconds in real files, so both ISO 8601 forms are accepted. The `JSONDecoder` and the date format style are static: `decode` runs once per line over hundreds of MB (NFR-7). De-duplication keys stay on the line as optional IDs.

`TranscriptAggregator` (`Activity/TranscriptAggregator.swift`, T-4.2, FR-24, FR-25, SPEC §8.3.3) is a value type over a `Calendar` (the zone that defines the local day; `.current` in the app). `add(_:)` counts a key (`message.id:requestId`, `message.id` alone when `requestId` is missing) once, the first line wins; a line with neither ID is counted and increments `linesWithoutKey` for diagnostics. `days()` returns core `ActivityDay`s oldest first: requests, sessions (unique `sessionId` per day, lines without one add none), total and per model `TokenCounts`. Malformed lines are counted by the caller from `decode` throws. It keeps one global seen-key set and no per-file bookkeeping, so dropping a file's entries on truncation or deletion (FR-26) needs T-4.3 to key entries by file or to rebuild.

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

Beyond the windows, `billingNote` is the first non-empty line, `insights` the "What's contributing" block parsed into an `Insights` value: unindented `label · summary` lines open periods, indented lines become rankings (`Top <x>: …`), shares (`<n>% of your usage …`) or, when no rule fits, shares without a percent ([[decisions/0023-structured-insights]]), `rawOutput` the output as received, ANSI codes included (P-10, P-11). Deciding `unsupportedPlan` from the note is left to the provider (T-2.5). The synthetic cases of SPEC §16.2 (model window, unknown window, `<1%`, ANSI) are inline strings in the tests, not fixture files.

`ClaudeLocator` (`Limits/ClaudeLocator.swift`, FR-6) is a stateless struct over `ProcessRunning`. `locate(override:)` runs the login shell once (`command -v claude`, then `$PATH` as the last line), then tries the override, the shell's answer and the four known locations in that order, and returns the first whose `--version` exits 0 within 10 s, with its version and the environment it passed: the app's environment with the login shell's PATH (SPEC §8.1.1). The probe reuses that environment. Caching lives in the provider (T-2.5), which is the only place that sees when the path stops working and also throttles re-resolution after a miss (SPEC §13); keeping hits and misses in one owner is why the locator holds no state. An invalid override falls through to the other candidates; SPEC FR-6 leaves this open.

`ClaudeCodeProvider` (`ClaudeCodeProvider.swift`, T-2.5) is one actor that is both the `UsageProvider` and its `LimitsSource` (`limits` returns `self`); a separate probe type only forwarded calls and leaked its cache to detection. The descriptor is a file-private `ProviderDescriptor.claudeCode` constant: symbol `terminal`, capabilities `limits` and `insights` until T-4 brings the `ActivitySource`, all four token categories, the §8.1.4 schedule policy with `needsNetwork` set (the probe asks Anthropic). The actor caches the locator's `Found` with the override it was resolved for, so a changed `pathOverride` locates again; the override is a closure the app wires to the setting. `fetch()` joins a running probe (FR-7), creates `providers/claude-code/probe/` owner-only through `JSONStore.createFolder` (it can be the first folder under the root, [[modules/core#Things that bite]]), runs `-p /usage --no-session-persistence` there with the located environment and a 30 s timeout, and maps the result: a launch error clears the cache and locates once more (a two-pass loop in `run()`), then `toolNotFound`; `timedOut` and cancellation pass through; a non-zero exit is `notLoggedIn` when the output says "login", "log in" or "logged in" as whole words, else `processFailed` with the last 500 characters of stderr; a billing note without "subscription" is `unsupportedPlan` ([[decisions/0017-unsupported-plan-source-error]]); zero windows is `unparseable`. `detectAvailability()` reuses the cache and reports only `notInstalled` or `available` with the version: `notSignedIn` is indistinguishable (R-2) and the plan needs a probe (ADR-017). `pushedUpdates()` is empty until the bridge (FR-39).

## Things that bite
- Cancelling one caller that joined a running probe cancels it for every joined caller (a `ponytail:` note marks it); the coordinator is the only caller, so joins are rare.
- An x86_64 `claude` without Rosetta fails `--version` too, so the locator never returns it: SPEC §13's Rosetta row shows up as `toolNotFound` today, and `ExecutableKind` (FR-36) is what tells the two apart.
- `Fixtures/usage/subscription-basic.txt` is reconstructed from Appendix A, not yet captured byte for byte as SPEC §16.2 requires; recapture it with the SPEC §16.6 command.
- Reset times resolve through `Calendar` in the clause's zone, so the Berlin DST change and New Year come out right; time only resets use `nextDate(after:)`, which already skips past `now`.
- Logged out and API key billing print the same bytes and exit 0 ([[research/r-2-usage-output-variants]]); the parser cannot tell them apart, and neither can the provider.
- The login shell answer counts only when it is an absolute path: for an alias `command -v` prints `alias claude=…`.
- A Finder-started app inherits launchd's PATH (`/usr/bin:/bin:/usr/sbin:/sbin`). An npm install is a `#!/usr/bin/env node` script, so `--version` fails without the login shell's PATH when `node` sits in `/opt/homebrew/bin`; hence the PATH is applied to validation, not only to the probe.
- Profile scripts may print to stdout, so the shell prints PATH last and the locator reads from the end.
- `DateFormatter` needs the `am`/`pm` suffix split off and upper-cased (`4:09am` → `4:09 AM`) before the P-7 formats match.

## Related
[[decisions/0002-usage-probe-primary-limits-source]] · [[decisions/0007-native-transcript-parsing]]
