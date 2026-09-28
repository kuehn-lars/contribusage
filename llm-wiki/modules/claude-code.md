---
type: module
status: active
updated: 2026-09-28
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

## Things that bite
- SPEC §8.1.3 and T-2.1 describe an existing `UsageParser.swift` with tests; that code is not in this repository yet, so T-2.1 either adds it or writes the parser from scratch.

## Related
[[decisions/0002-usage-probe-primary-limits-source]] · [[decisions/0007-native-transcript-parsing]]
