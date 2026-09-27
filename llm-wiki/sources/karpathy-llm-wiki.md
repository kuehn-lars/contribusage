---
type: source
status: active
updated: 2026-09-28
tracks: []
tags: [process, meta]
---
# Source: Karpathy, "LLM Wiki"

- **Origin:** "LLM Wiki" idea file, published as a GitHub gist · **Author:** Andrej Karpathy · **Ingested:** 2026-09-28

The idea document this vault is built on.

## Key points
- RAG re-derives knowledge from raw documents on every question, so nothing accumulates. Instead, an LLM **incrementally maintains a persistent, interlinked Markdown wiki**: knowledge is compiled once and then kept current.
- Three layers: **raw sources** (immutable), **the wiki** (owned by the LLM), and **the schema** (`CLAUDE.md` / `AGENTS.md`), which turns a generic chatbot into a disciplined maintainer.
- Operations: **ingest** (one source can touch 10–15 pages), **query** (good answers get filed back as pages), **lint** (contradictions, stale claims, orphans, gaps).
- `index.md` is the content catalog the LLM reads first. `log.md` is the append-only chronology with a grep-able entry prefix.
- Obsidian is the IDE, the LLM is the programmer, and the wiki is the codebase. Humans curate and ask; the LLM does the bookkeeping, which is the part humans abandon.

## How this vault adapts it to a code repository
| Karpathy | Here |
|---|---|
| raw sources | `raw/` for saved external originals (created on first use); the code itself (the truth about what is); `SPEC.md` (the contract) |
| wiki pages | `architecture/`, `modules/`, `decisions/`, `research/`, `concepts/`, `guides/`, `sources/` |
| schema | `AGENTS.md`, imported by `CLAUDE.md` for Claude Code |
| ingest · query · lint | the same, plus **record**: every turn that changes the repository updates the pages that describe it and `log.md` |
| (new) | `sessions/`: per-chat working memory with a `## Handover`, gitignored, so any agent resumes where the last one stopped and personal detail stays local |
| (new) | the **stranger test** separates what may be published from what stays in the session file |
| (new) | `tracks:` frontmatter maps pages to code paths, which lets lint detect stale pages |
| (new) | `tools/wiki.sh`: any agent can check the discipline with `lint`, and Claude Code hooks enforce it at the end of each turn ([[guides/llm-wiki-tooling]]) |
| optional search (qmd) | not needed yet; the index plus grep is enough at this size |

## Related
[[decisions/0012-llm-wiki-as-project-memory]]
