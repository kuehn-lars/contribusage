---
type: decision
status: accepted
updated: 2026-09-28
aliases: [ADR-001]
tags: [platform, ui]
---
# ADR-001: Native Swift and SwiftUI with `MenuBarExtra`

- **Decided:** 2026-09-28 · **Spec:** SPEC header, §9, §11 · **Supersedes:** —

## Context
The app sits in the menu bar all day. It has to look native, stay small in memory and cost almost nothing while idle (NFR-1, NFR-2, NFR-9).

## Options
| Option | For | Against |
|---|---|---|
| Swift and SwiftUI (`MenuBarExtra`) | Small footprint, native look, first-class menu bar support | macOS only (other platforms are a non-goal anyway) |
| Electron | Familiar web stack | Heavy runtime for a menu bar item |
| Tauri | Lighter than Electron | Web UI, a second toolchain |
| Python with rumps | Fast to sketch | Prototype quality only |

## Decision
Swift 6 and SwiftUI, with `MenuBarExtra` in `.window` style as the popover.

## Consequences
- `MenuBarExtra` limits shape the UI: no official "is open" binding, template-rendered labels (SPEC §20).
- Swift 6 strict concurrency applies to all code (NFR-11).
