---
type: research
status: answered
updated: 2026-10-04
tracks: [Packages/ContribusageKit/Sources/ContribusageClaudeCode/ClaudeCodeProvider.swift]
tags: [research, claude-code, scheduling, energy]
---
# R-1: Probe cost

- **Spec:** SPEC §17.0 R-1, NFR-5, NFR-1, §8.1.4, §8.1.5 · **Blocks:** T-5.21 · **Answered:** 2026-10-04

## Question
Does a `/usage` probe consume plan quota, and what does probing every minute cost the Mac? The answer sets the probe's default and minimum interval ([[decisions/0039-one-minute-probe]]).

## Method
- Claude Code 2.1.289, subscription plan, Apple M3. Every probe in an empty folder with the arguments of SPEC §8.1.1.
- `claude -p "/usage" --output-format json --no-session-persistence`: the result's cost and token fields.
- 20 probes 30 s apart (about 10.5 min), logging the session and weekly percentages each time. The agent running the test was idle for the last 16 probes; its own requests count against the same session window, so only idle steps are evidence.
- `/usr/bin/time -l` on three probes: wall clock, CPU and peak memory.
- NFR-1: the Release build (arm64) with `provider.claude-code.probeInterval` set to 1, popover closed, `ps -o time=` and the count of child processes every 10 s for about 9 min, `footprint` at start and end (the method of [[research/t-5-8-performance-energy]]).

## Findings
- The JSON result has `local_command: "usage"`, `num_turns: 0`, `duration_api_ms: 0`, every token count 0 and `total_cost_usd: 0`: `/usage` is answered without a model turn.
- Over the 16 idle probes the session percentage stayed at <n> % and the weekly one did not move. It rose by 2 points only while the agent was still working.
- Each probe takes about 2.3 s wall clock, 1.65 s CPU (user plus system) and 350 to 370 MB peak resident memory in the `claude` process. At one probe a minute that averages about 2.7 % of one core while awake; at 5 min about 0.55 %.
- The app itself, probing every minute: CPU time rose from 1.36 s to 1.78 s over 543 s, 0.08 % including the refresh passes (NFR-1 asks below 0.1 % without them). Footprint 22 to 23 MB. Child processes showed in the samples taken during a probe, never two at once.
- Consecutive probes print the same reset as "3:59am" and "4am", the drift [[decisions/0038-notification-cycles-and-delivery]] tolerates.

## Outcome
- No quota cost, so 1 min stays the minimum; the CPU per probe makes 5 min the default (NFR-5, §8.1.4, §8.1.5, §12, [[decisions/0039-one-minute-probe]] revised).
- T-5.21 done; `probesEveryFiveMinutesAndAtMostEveryMinute` checks the policy.
