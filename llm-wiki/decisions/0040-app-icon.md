---
type: decision
status: accepted
updated: 2026-10-04
aliases: [ADR-040]
tags: [design, icon, distribution]
tracks: [App/AppIcon.icon, Contribusage.xcodeproj]
---
# ADR-040: The app icon is the prompt mark in Liquid Glass, as an Icon Composer document

- **Decided:** 2026-10-04 · **Spec:** SPEC §2.3, T-5.23, Q-6 · **Supersedes:** —

## Context
The app had no icon. It shows in Finder, in notifications, in Login Items and in System Settings, so it is the face of the app wherever the menu bar is not. SPEC §2.3 rules out vendor logos and names. The icon should say "coding agent" before "GitHub", sit among the system's Liquid Glass icons on macOS 26 and later in light, dark, clear and tinted, and still read at 16 pt in a Finder list. The menu bar already has a mark, `prompt` ([[decisions/0035-drawn-menu-bar-label]]): a `›` and code lines that fill as a window is used.

## Options
Five rounds of renders through Icon Composer's `ictool` (the system's own Liquid Glass renderer, `--design-generation 27`), each in light and dark, the finalist in all six renditions and at 16 to 128 pt:

| Option | For | Against |
|---|---|---|
| The menu bar mark scaled up: `›` and three code lines | Same mark as the label | At icon size it reads as a list (Reminders) |
| A glass terminal card on orange | Warm, layered | Reads as Terminal or Console |
| `›` inside a gauge arc | Says "usage" | Reads as a speedometer; the prompt shrinks |
| `›` and one cursor line that fills like a meter | Bold, reads at 16 pt; prompt and meter in one shape | Close to the classic `>_` without a further cue |
| The same plus the agent's spark above the cursor's end | The spark names the agent; the line is its budget | The spark is a common AI cue, so it needs a calm treatment |

Palettes tried: indigo, blue, international orange, graphite, a dusk gradient, and a light background. Graphite read as Terminal, blue as generic, the dusk gradient as a social app.

## Decision
The prompt `›`, a cursor line filled two thirds in amber, and a four-point spark above the line's end, on a near-white background with a lavender tint in light mode and a near-black ink in dark mode. The prompt is an indigo gradient (light indigo in dark mode), the fill an amber gradient, the track a translucent pill. Everything is drawn as filled outlines in one Icon Composer document, `App/AppIcon.icon`: two glass groups (glyph above, track below) for depth, fill specializations for dark and tinted. The Xcode target sets `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`; `actool` compiles `Assets.car` for macOS 26 and later and `AppIcon.icns` for macOS 14 and 15.

## Consequences
- The prompt is a filled outline, not a stroked polyline: the flattened `.icns` fallback filled the open polyline into a blob.
- The tinted specialization sets every layer to white; without it the indigo prompt went dim in Tinted Dark.
- The README header (`docs/assets/header.svg`, `header-dark.svg`) draws the icon as a flat SVG of the same art on the Big Sur grid (824 pt continuous-corner shape at 100 pt), with drawn highlights in place of the glass. Change the icon in `App/AppIcon.icon` first, then the headers. They use the system font stack, so they render in SF Pro on a Mac and in the platform font elsewhere.
- The README screenshots come from the real `PopoverView` and `MenuBarArt` with the preview mock data, rendered by a scratch copy of the app whose entry point draws the views into PNGs; none of it is committed. They show only windows that the real `/usage` output prints.
- Claude Code's provider symbol is the SF Symbol `sparkle` (was `terminal`), so the spark appears wherever the app names the agent: the popover's group header, Settings and the menu bar badge. It stays a neutral system symbol (SPEC §2.3).
- Revisit if the menu bar mark changes, or if a macOS release changes the icon grid.
