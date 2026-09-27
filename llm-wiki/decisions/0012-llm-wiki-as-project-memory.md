---
type: decision
status: accepted
updated: 2026-09-28
aliases: [ADR-012]
tags: [process, wiki]
---
# ADR-012: An agent-maintained LLM wiki as the project memory

- **Decided:** 2026-09-28 · **Spec:** SPEC §0 · **Supersedes:** —

## Context
The project is built with coding agents. Each chat starts without memory, and what a chat learns disappears with it. The repository is public, so whatever becomes shared memory is published, while local working notes (paths, accounts, the conversation itself) must stay on the machine.

## Options
| Option | For | Against |
|---|---|---|
| SPEC.md and git history only | Nothing extra to maintain | Reasons, findings and "where we are" get lost between chats |
| A single notes file | Simple | Grows into an unstructured dump; no links, no checks |
| An LLM wiki ([[sources/karpathy-llm-wiki]]) with local session files | Structured, linked and linted memory; handover between chats; personal detail stays local | Every turn spends effort on bookkeeping |

## Decision
`llm-wiki/` is an Obsidian vault that agents maintain as described in `AGENTS.md`: orient at the start of every turn, record at the end. Session files with a `## Handover` are gitignored; the committed vault describes only the project and passes the stranger test. `tools/wiki.sh` lints the vault and Claude Code hooks enforce the protocol ([[guides/llm-wiki-tooling]]).

## Consequences
- Knowledge compounds: a new chat resumes from the last handover instead of re-deriving context.
- Bookkeeping is part of every turn, and the Stop hook makes skipping it visible.
- A fresh clone has the vault but no session history; SPEC §17 and the log carry the public state.
