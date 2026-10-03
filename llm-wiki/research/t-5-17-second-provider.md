---
type: research
status: answered
updated: 2026-10-04
tracks: []
tags: [research, provider, codex]
---
# T-5.17: Second provider evaluation

- **Spec:** SPEC §17 T-5.17, §19.1 Q-7, §2.4 · **Blocks:** nothing (v1 ships without a second provider, [[decisions/0037-no-second-provider-for-v1]]) · **Answered:** 2026-10-04

## Question
Which AI coding tool could become the second provider (Q-7), and which of its capabilities pass the provider gate (SPEC §2.4)?

## Method
- Codex CLI 0.157.1 and GitHub Copilot CLI 1.0.91: read the files each tool writes under `~/.codex/` and `~/.copilot/` (key names and event types only, no message content; `~/.codex/auth.json` and every credential store left untouched), about 100 Codex session files.
- Gemini CLI: documentation only, it was not installed.
- Official documentation, 2026-10-04: Codex [authentication](https://learn.chatgpt.com/docs/auth), [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference), [hooks](https://learn.chatgpt.com/docs/hooks); GitHub [Copilot requests](https://docs.github.com/en/copilot/reference/copilot-billing/request-based-billing-legacy/copilot-requests); Gemini CLI [quotas and pricing](https://geminicli.com/docs/resources/quota-and-pricing/).

## Findings

### Candidates

| Tool | Limits | Activity | Insights | Gate outcome |
|---|---|---|---|---|
| Codex CLI | Its own session files (undocumented format) | The same files | none | limits and activity, files only |
| Copilot CLI | Only on github.com billing pages or an undocumented quota endpoint | `session.shutdown` events: premium requests, token metrics per session | none | activity only |
| Gemini CLI | A daily request quota per plan, shown interactively in `/stats` | Local chat logs | none | not assessed, no fixtures possible |

Codex is the only candidate whose limits pass the gate, and it differs from Claude Code in ways that would actually test the provider abstraction (below).

### Codex: interface inventory (gate step 2)

| Interface | Documented | Exposes | Usable |
|---|---|---|---|
| `$CODEX_HOME/sessions/YYYY/MM/DD/rollout-<timestamp>-<uuid>.jsonl` (default `~/.codex`) | No: the configuration reference names no format | Limits and per turn token counts (below) | Yes, files the tool writes (principle 1); format changes need fixtures per version, as for Claude Code transcripts |
| `/status` in the TUI | Yes | The same windows, as text | No: interactive only, no print mode |
| Hooks (`hooks.json`, `[hooks]`) and `notify` | Yes | Lifecycle events with `session_id`, `transcript_path`, `model`, `turn_id`; no token usage, rate limits or plan | Only as a trigger: `transcript_path` names the file to read, which `FileEvents` already gives |
| App server `account/rateLimits/read` | In the source | Current limits without sending a message | No: the request goes to OpenAI's backend with the user's credentials (principle 2) |
| `codex exec --json` | Yes | Events of a turn it runs | No: each run is a model turn that consumes quota; there is no `/usage`-style free probe |
| `~/.codex/auth.json` or the keychain entry | Yes (as a credential store) | Tokens | Never (principle 2; the docs say to treat it like a password) |

### Codex: session file shape

Each line is `{"timestamp", "type", "payload"}`. The relevant types:

- `session_meta` (first line): `cli_version`, `cwd`, `model_provider`, `originator`, `source`, plus account identifiers (`creator_account_id`, `creator_user_id`) and the base instructions. A parser must skip the identifiers and never store them.
- `turn_context`: `model`, `timezone`, `cwd`, `effort` and policy fields per turn.
- `event_msg` with `payload.type == "token_count"`:
  - `info.last_token_usage` and `info.total_token_usage`: `input_tokens`, `cached_input_tokens`, `cache_write_input_tokens`, `output_tokens`, `reasoning_output_tokens`, `total_tokens`. In the samples `total_tokens = input_tokens + output_tokens`, so `input_tokens` includes the cached part. `info` can be `null`.
  - `rate_limits` (`null` in many events): `limit_id` (`"codex"`), `primary` and `secondary` windows, each `{used_percent, window_minutes, resets_at}` (Unix seconds) or `null`, `credits {has_credits, unlimited, balance}`, `plan_type`, `rate_limit_reached_type`, `spend_control_reached`, `individual_limit`.
- `response_item`, `user_message`, `agent_message`: conversation content, never read.

Observed on one plan: only `primary`, with `window_minutes` 43200 (30 days) and `secondary` `null`. Public reports describe a 5 hour primary and a weekly secondary on paid plans. So the windows differ by plan and are named by duration, not by label.

### How Codex would fit

- **Limits as a pushed source** ([[decisions/0036-pushed-limits-and-debug-fake-provider]]): watch the sessions folder with `FileEvents`, read the newest `rate_limits` from the appended lines, emit a `LimitsReport` through `pushedUpdates()`. No polling and no process, so it adds no idle cost (principle 5).
- **Window classification** from `window_minutes`: 300 → session, 10080 → weekly, anything else → other with a label made from the duration ("30 days"). This is the first provider whose labels the app writes itself, so the labels need a String Catalog (ADR-031, ADR-033).
- **Staleness:** the values change only when Codex runs a turn. A reset time in the past means the window has reset, but its new percentage is unknown until the next turn, and must be shown as unknown (principle 4), not as 0 %.
- **Activity** from the same files: `last_token_usage` per `token_count` event, attributed to the day of the event's `timestamp` and to the model from the preceding `turn_context`. Token categories: input minus cached → input, cached → cacheRead, output; `reasoning_output_tokens` has no `TokenCategory` and would either count as output or need a new category, which is the heatmap metric question this task was meant to raise (FR-48).
- **Plan** (FR-50, T-6.10): `plan_type` is in the file, so Codex would report its plan without an extra interface; R-6 stays open for Claude Code only.
- **Network:** none (`needsNetwork` false).

### Not done in this evaluation (gate steps still open)
- Step 1: a terms review of OpenAI's Terms of Use and the Codex documentation in the style of SPEC §2.1. The authentication page covers credential storage but says nothing about third-party tools reading local files.
- Steps 4–6: R-items (file rotation and retention, multi-window fixtures from a paid plan, behaviour with `history.persistence` off), the SPEC §8 provider section and a phase in §17.

## Outcome
- [[decisions/0037-no-second-provider-for-v1]]: v1 ships with Claude Code only; Codex is the named candidate for after v1.
- SPEC: T-5.17 ticked, Q-7 answered, §7.6 names Codex and links here. No fixtures were captured; the session files contain account identifiers and need scrubbing (SPEC §16.2) when the gate is resumed.
