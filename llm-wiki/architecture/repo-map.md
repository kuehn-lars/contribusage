---
type: architecture
status: active
updated: 2026-09-28
tracks: [.github/workflows, App, Packages/ContribusageKit/Package.swift]
tags: [structure]
---
# Repository map

Every top-level entry of the repository and of the vault, and what it is for. `wiki.sh lint` compares the first code block below with the files on disk (the repository root and the vault's top level), so the tree cannot drift unnoticed. The full source layout, including what is still planned (`scripts/`), is in SPEC §15.2; entries join this tree when they are created, and each build target has its page under `modules/`.

```text
contribusage/
├── .claude/settings.json   Claude Code hooks that run the wiki protocol
├── .github/workflows/      CI: package tests (warnings as errors), app build, architecture checks, wiki lint
├── .gitignore
├── .swift-format           swift-format settings (4 spaces, 120 columns)
├── AGENTS.md               agent protocol: orient, work, record; publish policy; hard rules
├── App/                    the app target: AppState, Popover/; a folder synchronised with Xcode
├── CLAUDE.md               imports AGENTS.md for Claude Code
├── Contribusage.xcodeproj  the Xcode project: one app target linking the package products
├── Packages/               ContribusageKit: every target but the app; fixtures in each test target's `Fixtures/` (SPEC §16.2)
├── README.md
├── SPEC.md                 the contract: requirements, tasks, research items
└── llm-wiki/               the memory: this Obsidian vault
    ├── .obsidian/          shared vault settings (only app.json is committed)
    ├── _templates/         one template per page type
    ├── architecture/       cross-cutting structure as built
    ├── decisions/          ADRs, NNNN-slug.md
    ├── guides/             how-tos
    ├── index.md            catalog of every page
    ├── log.md              chronological change log
    ├── modules/            one page per build target
    ├── overview.md         hub: what, how the pieces fit
    ├── research/           findings for the spec's R-items
    ├── sessions/           session files, local only (gitignored)
    ├── sources/            summaries of external sources
    └── tools/              wiki.sh and its regression test
```

Folders named in `AGENTS.md` but not yet present (`concepts/`, `raw/`) are created with their first file.
