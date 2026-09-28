---
type: research
status: answered
updated: 2026-09-29
tracks: [Packages/ContribusageKit/Tests/ContribusageClaudeCodeTests/Fixtures/usage]
tags: [research, claude-code, probe]
---
# R-2: `/usage` output without a subscription

- **Spec:** SPEC §17.0 R-2 · **Blocks:** T-2.2, SPEC §13 · **Answered:** 2026-09-29

## Question
What exit code, stdout and stderr does `claude -p "/usage"` produce when logged out and when billed by API key (SPEC §8.1.3 P-10, §13)?

## Method
Claude Code 2.1.284, each variant run once from an empty temporary folder with a fresh empty `CLAUDE_CONFIG_DIR`, so the real login stays untouched:

```sh
CLAUDE_CONFIG_DIR=$(mktemp -d) claude -p "/usage" --no-session-persistence </dev/null
CLAUDE_CONFIG_DIR=$(mktemp -d) ANTHROPIC_API_KEY=sk-ant-dummy claude -p "/usage" --no-session-persistence </dev/null
```

The subscription variant is Appendix A.

## Findings
- Both variants exit 0, write nothing to stderr and print byte-identical stdout: the session cost summary, first line `Total cost:            $0.0000`, no usage windows, no insights block.
- No output mentions logging in, so a logged out CLI cannot be told apart from API key billing by its `/usage` text.
- The empty config folder did not pick up the existing login (no subscription line), so no second macOS account was needed.
- The dummy key is not rejected; the summary reports `Total duration (API):  0s`, so `/usage` apparently makes no API call (network traffic was not monitored).
- Even with `--no-session-persistence`, the CLI creates `backups/`, `projects/`, `sessions/` and `.claude.json` in its config folder.

## Outcome
- Fixtures `usage/not-subscription.txt` and `usage/logged-out.txt` (captured byte for byte, identical), tested in `UsageParserTests`.
- SPEC P-10 names the exact first line; SPEC §13 "Not logged in" notes that logged out lands in `unsupportedPlan`, whose message fits both cases.
