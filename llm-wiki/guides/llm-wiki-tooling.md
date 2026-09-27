---
type: guide
status: active
updated: 2026-09-28
tracks: [llm-wiki/tools/wiki.sh, llm-wiki/tools/test-wiki.sh, .claude/settings.json]
tags: [tooling, wiki]
---
# llm-wiki tooling

`llm-wiki/tools/wiki.sh` checks that the vault follows the protocol in `AGENTS.md`, for any agent and for humans; Claude Code runs it automatically through hooks. It needs only bash and git.

## Commands
| Command | What it does |
|---|---|
| `wiki.sh context` | Prints where work stands: the latest session's Handover, git status, the last five log entries, the index. |
| `wiki.sh new-session <slug> [agent]` | Creates `sessions/YYYY-MM-DD-HHMM-<slug>.md` from the template and carries the previous Handover over, so the chain holds even if a chat ends early. |
| `wiki.sh lint` | Structural health check; exits 1 on any finding. |
| `wiki.sh hook <event>` | Entry point for the Claude Code hooks below. |
| `test-wiki.sh` | Regression test for `wiki.sh`, run against a throwaway copy of the repository. Run it after changing `wiki.sh`. |

## Claude Code hooks
`.claude/settings.json` wires three hooks:

| Hook | Effect |
|---|---|
| SessionStart | Injects `context`. A new chat is told to create its session file; a resumed or compacted one to re-read its own. |
| UserPromptSubmit | Saves the repository's file list to a per-turn marker in `$TMPDIR` and reminds the agent of the protocol. |
| Stop | Blocks the end of the turn (exit 2) until a session file changed during the turn and, if any file outside the vault was added, removed or edited, a vault page too. It lets the turn end in plan mode and on the second stop attempt. |

Other agents get no hooks: they follow `AGENTS.md` and run `lint` themselves.

## Lint findings
| Finding | Fix |
|---|---|
| `no frontmatter`, `'updated:' must be a date`, `unknown type`, `status … is not one of` | Frontmatter must match the vault table in `AGENTS.md`. |
| `file name is not kebab-case` | Rename the file (Obsidian updates links). |
| `not listed in index.md` | Add a line to `index.md`. |
| `broken link`, `no heading … in` | Fix the link target or the heading. |
| `links into local-only sessions/` | Remove the link; move what matters into a committed page. |
| `stale — <path> changed after this page` | Re-read the tracked code; update the page, or bump `updated:` if it still holds. |
| `tracks a missing path` | Fix `tracks:` after a move or deletion. |
| `names: … used in more than one folder` | Rename one page; bare `[[name]]` links would be ambiguous. |
| `decisions: name must be NNNN-slug.md`, `number … is used twice` | Renumber the newer ADR (parallel branches can collide). |
| `raw originals are immutable` | Restore the file under `raw/` from git. |
| `repo-map: … is missing from the tree`, `the tree lists …, which does not exist` | Update the tree in [[architecture/repo-map]]. |
| `has no ## Handover section`, `first heading must be ## Handover` | Fix the session file. |
| `session files are tracked by git`, `sessions/ is not ignored` | `git rm --cached` the files and fix `.gitignore`: local memory is about to be published. |

## Limits
- Staleness comes from git: a page is stale when a tracked path's last commit, or an uncommitted edit, is newer than the page's. A page and its code both edited in the working tree count as updated together.
- The Stop gate checks that pages changed, not that they are right; the index, the handover and lint findings are the review surface.
- The repo map check covers the repository root and the vault's top level only.
- Spec citations (`SPEC §…`, `FR-…`) are plain text and not checked.

## Reuse in another repository
1. Copy `llm-wiki/tools/`, `llm-wiki/_templates/`, `llm-wiki/.obsidian/app.json`, `llm-wiki/sources/karpathy-llm-wiki.md`, `.claude/settings.json`, `CLAUDE.md`, and the llm-wiki lines of `.gitignore`.
2. Copy `AGENTS.md`. Its sections "Every turn", "What goes where" and "The vault" are generic; rewrite the introduction, "Work", "Hard rules" and "Commands" for the new project.
3. Write `index.md`, `log.md`, `overview.md` and `architecture/repo-map.md`, then one page per build target and an ADR for adopting the vault.
4. Adapt the file names `test-wiki.sh` uses (for example `SPEC.md`), then run it and `wiki.sh lint` until both are clean.
