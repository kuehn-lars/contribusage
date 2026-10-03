---
type: decision
status: accepted
updated: 2026-10-04
aliases: [ADR-037]
tags: [provider, codex, scope]
tracks: []
---
# ADR-037: No second provider for v1

- **Decided:** 2026-10-04 · **Spec:** SPEC T-5.17, Q-7, §7.6, §2.4 · **Supersedes:** —

## Context
T-5.17 runs the provider gate for a second AI coding tool before v1, so a second real shape can test the layout and the heatmap metric. [[research/t-5-17-second-provider]] surveyed Codex CLI, Copilot CLI and Gemini CLI. Only Codex passes the gate for limits; it would do so through its own session files, whose format is undocumented. The gate's terms review, R-items, provider section and phase are not done yet.

## Options
| Option | For | Against |
|---|---|---|
| Integrate Codex in v1 | Tests the provider abstraction with a second real shape: pushed limits, windows named by duration, reasoning tokens, a plan in the data | A new phase before v1; an undocumented format to follow per version; gate steps 1 and 4–6 still open |
| Integrate Copilot CLI (activity only) | Session summaries in local files | No limits, the app's main purpose; a weak test of the layout |
| No second provider for v1 | v1 scope unchanged; the evaluation is recorded for later | The layout and heatmap with two real providers are tested only with `FakeProvider` and `DebugFakeProvider` |

## Decision
v1 ships with Claude Code as its only AI coding provider. Codex is the candidate for the next provider. The research page holds its interface inventory and an integration sketch; the gate resumes there after v1.

## Consequences
- The two-provider layout stays covered by `FakeProvider` (tests) and `DebugFakeProvider` (the app under its flag, [[decisions/0036-pushed-limits-and-debug-fake-provider]]).
- Open questions for the Codex gate: whether `reasoning_output_tokens` counts as output or needs its own `TokenCategory` (FR-48 heatmap metric), and app-written window labels that need a String Catalog (ADR-033).
- T-6.10 (plan display) gets its first real plan source with Codex (`plan_type` in its session files).
- Revisit when v1 is released, or earlier if Codex documents its session file format or a status interface.
