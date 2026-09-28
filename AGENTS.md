# AGENTS.md

Instructions for every coding agent in this repository. Claude Code loads this file through `CLAUDE.md`.

**contribusage** is a native macOS menu bar app for Apple Silicon (Swift 6, SwiftUI) that shows the usage of AI coding tools (v1: Claude Code, behind a provider framework) and GitHub contributions. Two documents govern the work, and every piece of knowledge lives in exactly one of them:

| | `SPEC.md`: the **contract** | `llm-wiki/`: the **memory** |
|---|---|---|
| Answers | What must be built | How it is built, why, what was learned, where work stands |
| Holds | Requirements with stable IDs (`FR-`, `NFR-`, `US-`), tasks (§17), open research (§19) | Module pages, ADRs, research findings, guides, the change log |
| Changes when | The contract changes, or reality proves it wrong | Every turn that changes the repository or learns something |

Code follows the spec; the vault describes the code. When they disagree, the code is the truth about what *is* and the spec about what *should be*: fix the one that is wrong in the same turn.

## Every turn: orient, work, record

The vault is the first and the last thing you touch in every turn, including turns that only answer a question.

### 1. Orient

- **New chat:** read the output of `llm-wiki/tools/wiki.sh context` (in Claude Code the SessionStart hook has already printed it): the last handover, git state, recent log, index. Then create your session file with `llm-wiki/tools/wiki.sh new-session <topic-slug> <agent-name>`; it is yours for the whole chat.
- **Continuing chat** (resumed or compacted): re-read your session file.
- Open the pages from `llm-wiki/index.md` that the prompt touches, and the spec sections they cite. SPEC.md is ~1,700 lines: grep it for IDs and section numbers rather than reading it whole.

Orientation is done when you can name the pages, spec sections and files the prompt touches.

### 2. Work

Code changes follow SPEC §0:

1. Take the task from SPEC §17 and read every requirement it references.
2. Write the tests first, in the matching test target under `Packages/ContribusageKit/Tests/`, with fixtures and fakes from `ContribusageTestSupport`.
3. Make the smallest change that turns them green, in the target that owns it (the page under `llm-wiki/modules/` says which).
4. Run the tests (see Commands); build the app too when the app target changed.
5. Tick the task in SPEC §17. Where the implementation departs from the spec, change the spec in the same change and record the reason as an ADR.

Research items (SPEC §17.0) produce a page in `llm-wiki/research/` with method and findings; the outcome goes into the spec, and into an ADR when it decides something.

Throughout: state the assumptions you act on, and when the spec leaves a real choice open, lay out the options and ask. Every changed line traces back to the task. "Done" is a check that would fail without the change.

### 3. Record

Before the final reply:

1. **Session file** (local): rewrite `## Handover` as a whole so it stands alone, and append one `## Log` entry for this message.
2. **Vault** (public), when the turn changed the repository or produced knowledge worth keeping:
   - update every page that describes what changed, and its `updated:` date;
   - create pages for new modules, decisions, research and guides from `llm-wiki/_templates/`, and list each in `index.md`;
   - append an entry to `log.md`.
3. Run `llm-wiki/tools/wiki.sh lint`.

Recording is done when lint prints `wiki lint: clean` and a fresh agent could continue from the handover alone. In Claude Code a Stop hook holds the turn open until the session file (and, if the repository changed, the vault) has been updated.

Subagents report back to the main agent, which owns the session file and the vault.

## What goes where

This repository is public. The vault documents the project and its development; the people behind it stay out of it. Before writing a line into the vault, apply the **stranger test**: would this line tell a stranger anything about who works here, their machine, their accounts or their habits? Then it belongs in the session file, or nowhere.

| Vault (committed, public) | Session file (gitignored, local) | Nowhere, not even locally |
|---|---|---|
| Design, behaviour, decisions and their reasons | The conversation: requests, preferences, feedback | Secrets: tokens, API keys, passwords, cookies, credential files |
| Research method and scrubbed results | Local paths, user names, machine, OS and hardware details | Prompt or transcript content from other projects |
| Tool versions and formats the project depends on | Accounts, logins, plans, personal usage numbers | Personal data of anyone else |
| Dates (`YYYY-MM-DD`) | Times of day, installed tools, skills and plugins | |

Write the vault in the project's voice: the subject is the code, the decision or the finding ("The probe runs in an empty folder because…"), never a person. Use placeholders for anything personal: `~/…` for paths, `octocat` for logins, `<n>` for personal numbers. Fixtures follow the same rule (SPEC §16.2).

## The vault

`llm-wiki/` is an Obsidian vault (open that folder, not the repository root). `architecture/repo-map.md` shows every folder.

| Folder | `type` | `status` | Holds |
|---|---|---|---|
| (root) | `overview`, `index`, `log` | `active` (index and log: none) | Hub, catalog, change log |
| `architecture/` | `architecture` | `planned` `active` `stable` `deprecated` | Cross-cutting structure as built: repo map, data flow, persistence layout |
| `modules/` | `module` | same | One page per build target: app, core, each provider, GitHub, test support |
| `decisions/` | `decision` | `proposed` `accepted` `superseded` | ADRs as `NNNN-slug.md`; `ADR-NNN` in the spec is `decisions/0NNN-…` |
| `research/` | `research` | `open` `answered` | Findings for the spec's R-items and other investigations |
| `concepts/` | `concept` | `planned` `active` `stable` `deprecated` | Domain knowledge the spec does not hold: observed formats, platform behaviour |
| `guides/` | `guide` | same | How-tos: tooling, fixture capture, release |
| `sources/` | `source` | same | Summaries of external documents; saved originals go in `raw/` and never change |
| `sessions/` | none | none | Session files, one per chat, `## Handover` first; never committed, never linked |

A folder is created with its first page and added to the repo map. Page rules (lint enforces the checkable ones):

- Frontmatter: `type`, `status`, `updated: YYYY-MM-DD`, `tags`, and `tracks:` listing the repository paths the page describes; lint flags the page stale when one of them changes after it. Decisions carry `aliases: [ADR-NNN]`.
- File names are kebab-case and unique across folders.
- Link pages with vault-absolute wikilinks: `[[modules/core]]`, `[[decisions/0003-official-interfaces-only#Decision]]`. Cite the spec by section or ID (`SPEC §8.1.3`, `FR-8`); its IDs are stable.
- One meaning lives on one page: summarise and link. Spec content is cited, never restated.
- `log.md` entries read `## [YYYY-MM-DD] <type> | <title>` with one to three bullets; the types follow conventional commits: `feat` `fix` `refactor` `test` `docs` `spec` `decision` `research` `wiki` `chore`.

## Hard rules (SPEC §2)

- Leave every tool's credentials untouched (for Claude Code: its credential file and Keychain items), and call no vendor backend (`api.anthropic.com`, `claude.ai`, or any other tool vendor's) from app code.
- Run `claude` only with the arguments in SPEC §8.1.1 and FR-6.
- The GitHub token goes only through `SecretStore` (Keychain) and never into logs.
- `ContribusageCore` imports no provider target and not `ContribusageGitHub`. Provider code lives only in its provider target, and only after its provider section exists in SPEC §8.
- The app target holds views and wiring only; blocking work stays off the main actor.
- arm64 only: `ARCHS` stays `arm64`.
- Swift 6 language mode, strict concurrency, zero warnings.
- A failing test is fixed in the code. A wrong fixture is corrected with the reason in the commit message.

## Commands

| Purpose | Command |
|---|---|
| Package tests | `swift test --package-path Packages/ContribusageKit -Xswiftc -warnings-as-errors` |
| One target's tests | `swift test --package-path Packages/ContribusageKit -Xswiftc -warnings-as-errors --filter ContribusageClaudeCodeTests` |
| Build the app | `xcodebuild -project Contribusage.xcodeproj -scheme Contribusage -configuration Debug -derivedDataPath .build/xcode build` |
| Swift lint | `swift format lint --strict -r App Packages` |
| Architecture check | `lipo -archs .build/xcode/Build/Products/Release/contribusage.app/Contents/MacOS/contribusage` prints `arm64` |
| CI | `.github/workflows/ci.yml` runs the package tests and lint, the Release build with the `arm64` check, and the wiki lint on every pull request |
| Wiki | `llm-wiki/tools/wiki.sh context`, `new-session <slug> [agent]`, `lint` |
| Wiki tooling test | `llm-wiki/tools/test-wiki.sh` (after changing `wiki.sh`) |
