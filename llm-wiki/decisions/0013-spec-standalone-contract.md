---
type: decision
status: accepted
updated: 2026-09-28
aliases: [ADR-013]
tags: [process, spec, wiki]
---
# ADR-013: SPEC.md stays a standalone contract beside the vault

- **Decided:** 2026-09-28 · **Spec:** SPEC §0, §18, Appendix B · **Supersedes:** —

## Context
SPEC.md (~1,800 lines) predates the vault and overlapped it in three places: a decision log (§18), an agent-instructions template (Appendix B), and task status (§17). Two copies of one meaning drift apart.

## Options
| Option | For | Against |
|---|---|---|
| Move SPEC.md into the vault as one page | Wikilinks into spec headings, checked by lint | The contract becomes wiki content; less discoverable; still one very large page |
| Split SPEC.md into vault pages | Agents load only the section they need | Breaks one reviewable contract with dense cross-references; high churn |
| Keep SPEC.md at the root; give every overlap one owner | Conventional place for a spec-driven project; stable IDs already give precise addresses | Obsidian cannot link outside the vault, so spec citations are plain text |

## Decision
SPEC.md stays at the repository root as the contract. The vault cites it by section and ID (`SPEC §8.1.3`, `FR-8`) and never restates it. Overlaps moved to one owner:
- Decisions: the ADR table left §18 and became `decisions/0001` to `0011`, keeping their IDs; §18 now points here.
- Agent instructions: Appendix B was replaced by `AGENTS.md`.
- Status: the §17 checkboxes are the only task status; the vault keeps no second copy.

## Consequences
- Spec citations in the vault are not lint-checked; the spec's rule that IDs never change keeps them valid.
- Agents grep the spec by ID instead of loading it whole.
