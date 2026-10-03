---
type: decision
status: accepted
updated: 2026-10-04
aliases: [ADR-035]
tags: [menu-bar, ui, design]
tracks: [App/MenuBar/MenuBarArt.swift, App/MenuBar/MenuBarItem.swift, Packages/ContribusageKit/Sources/ContribusageCore/Models/MenuBarLabel.swift]
---
# ADR-035: The menu bar label is one drawn, colored image with seven styles

- **Decided:** 2026-10-04 · **Spec:** FR-12, FR-46, FR-51, SPEC §11.1, §20 · **Supersedes:** §11.1's monochrome template and gauge symbols

## Context
T-5.10 shipped the label as an SF Symbol gauge plus text, rendered as a template, because §20 said colors in a `MenuBarExtra` label are ignored. The gauge is the system's generic symbol, so the most visible part of the app looked like any other status item and said nothing about coding agents. The label is the app's main surface, so it should carry the app's identity, show color, and let people pick how much it shows. §2.3 still rules out vendor logos.

## Options
| Option | For | Against |
|---|---|---|
| Keep SF Symbols as templates | System handles light, dark and highlight | No color, no identity; the gauge reads like a system meter |
| Own `NSStatusItem` instead of `MenuBarExtra` | Full control of the button | Rebuilds the `.window` popover and its open trigger |
| One non-template `NSImage` with a drawing handler in the `MenuBarExtra` label | Color and custom shapes; the handler runs in the status item's appearance, so `labelColor` follows the bar | The app draws text and spacing itself; derived colors must be made while drawing |

## Decision
`MenuBarArt` draws glyph, badge and text into one non-template `NSImage`; `MenuBarItem` shows it with `Image(nsImage:)`. A spike confirmed that the image keeps its colors in the real menu bar and that the handler runs under `NSAppearanceNameVibrantDark` on a dark bar. Six styles came out of three rounds of rendered prototypes at menu bar size: `prompt` (the app's mark: `›` and three code lines that fill as the window is used, "the agent is typing"), `rings` (window and companion window, concentric), `ring` (number inside, the most compact), `line` (`›` and a filling cursor line), `heatmap` (three weeks of the source's activity), `sharedHeatmap` (the shared heatmap's layers over the same three weeks, split cells as in FR-49 Combined, with 4.2 pt cells so two stripes stay apart) and `text`. Dropped in review: a stroke-trimmed `>_` (fill unreadable), a liquid-filled chevron (read as a "next" arrow), braces and a terminal tile (read as a battery or as the Terminal app), a 12-week grid and 14 bars (noise at 2 pt cells), and a ring with a chevron inside (read as a button). Colors: provider hue (default), by usage (§11.4), accent, monochrome, custom.

## Consequences
- The label works in every menu bar appearance without template rendering; the screenshots and the light/dark matrix are the check, since no test can see the menu bar.
- `MenuBarLabel` carries values (meter, companion, stale, title, source) instead of a symbol name, so a new style needs no core change.
- The heatmap style adds the menu bar provider to the activity demand, the shared one every layer of the shared heatmap, its hidden block notwithstanding (FR-46).
- The heatmap styles never turn red: a red Claude Code stripe next to GitHub's green failed the color blindness rule of [[decisions/0032-shared-heatmap]] in the light and dark review render, so the value text carries the 90 % warning there.
- Revisit when `MenuBarExtra` gains colored labels natively, or if a macOS release stops passing the status item's appearance to the handler.
