---
type: overview
status: active
updated: 2026-09-29
tracks: []
tags: [hub]
---
# contribusage

A native macOS menu bar app for Apple Silicon that shows how much of an AI coding plan is left and when it resets (v1: Claude Code), coding activity on this Mac, and the GitHub contribution graph. It uses only official interfaces and never touches another app's credentials ([[decisions/0003-official-interfaces-only]]).

Where work stands: the task checkboxes in SPEC §17 and the latest entries in [[log]].

## How the repository is organised
- **`SPEC.md`: the contract.** Requirements with stable IDs, the task plan, open research. Code follows it ([[decisions/0013-spec-standalone-contract]]).
- **This vault: the memory.** How things are built, why, what was learned, and what changed when ([[decisions/0012-llm-wiki-as-project-memory]]).
- **`AGENTS.md`: the protocol.** How every agent orients in the vault, works against the spec and records the result.

## System at a glance
Dependency direction: `ContribusageClaudeCode → ContribusageCore ← ContribusageGitHub`. The app depends on all three and is the only place providers are registered (SPEC §9.1).

| Target | Page | Role |
|---|---|---|
| App | [[modules/app]] | SwiftUI shell: menu bar, popover, Settings |
| `ContribusageCore` | [[modules/core]] | Provider-neutral models, scheduling, persistence, seams |
| `ContribusageClaudeCode` | [[modules/claude-code]] | The v1 provider: `/usage` probe and transcripts |
| `ContribusageGitHub` | [[modules/github]] | Contribution calendar and statistics |
| `ContribusageTestSupport` | [[modules/test-support]] | Fakes, `FakeProvider`, conformance suite |

Milestones (SPEC §17): M1 Claude Code limits in the popover → M2 GitHub → M3 activity → M4 v1.0 with the menu bar label → M5 extras and release.
