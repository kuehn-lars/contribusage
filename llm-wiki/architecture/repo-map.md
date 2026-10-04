---
type: architecture
status: active
updated: 2026-10-04
tracks: [.github/workflows, App, Packages/ContribusageKit/Package.swift, docs, LICENSE]
tags: [structure]
---
# Repository map

Every top-level entry of the repository and of the vault, and what it is for. `wiki.sh lint` compares the first code block below with the files on disk (the repository root and the vault's top level), so the tree cannot drift unnoticed. The full source layout, including what is still planned (`scripts/`), is in SPEC §15.2; entries join this tree when they are created, and each build target has its page under `modules/`.

```text
contribusage/
├── .claude/settings.json   Claude Code hooks that run the wiki protocol
├── .github/workflows/      CI: package tests (warnings as errors), app build, architecture checks, String Catalog sync check, wiki lint, the GitHub release on a version bump
├── .gitignore
├── .swift-format           swift-format settings (4 spaces, 120 columns)
├── AGENTS.md               agent protocol: orient, work, record; publish policy; hard rules
├── App/                    the app target: AppIcon.icon (the Icon Composer app icon, ADR-040), ContribusageApp (the scenes), MenuBar/ (the menu bar item with its minute tick and `MenuBarArt`, which draws the label in each style, GitHub's meters included), AppState and its live wiring (including the demand of the popover layout and the menu bar, FR-46), AppState+Copy (the copied statistics and diagnostics texts), ProviderRegistration (each provider with its live seams), DebugFakeProvider (US-11's second provider, only with `CONTRIBUSAGE_FAKE_PROVIDER`), SystemConditions, Popover/ (sections, the shared heatmap block with its keyboard navigation and VoiceOver, the shared state views and buttons, mock data), Settings/ (the Settings scene: General (menu bar mode, provider, style tiles and color, launch at login, notifications) and Advanced (data folder, caches, diagnostics) and the shared `IntervalPicker` in `SettingsView`, `PopoverTab` (block order by drag and drop, visibility, sections, heatmap membership and style), `ProvidersTab`, `GitHubTab` with the GitHub switch), Notifications/ (delivery: a queue that posts notes 3 s apart, one thread per provider, and asks for permission on the first note), Resources/ (the app's String Catalog, ADR-031); a folder synchronised with Xcode
├── CLAUDE.md               imports AGENTS.md for Claude Code
├── CONTRIBUTING.md         the contributor guide: build, rules, pull requests
├── LICENSE                 MIT
├── Contribusage.xcodeproj  the Xcode project: one app target linking the package products
├── docs/assets/            README art: header SVGs (light and dark) with the icon drawn flat, screenshots, the 1280×640 social preview (SVG source and the PNG uploaded under Settings → Social preview)
├── Packages/               ContribusageKit: every target but the app; fixtures in a test target's `Fixtures/` (SPEC §16.2; so far Claude Code and GitHub); the core's String Catalog in its `Resources/`, declared as a resource in `Package.swift`
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
