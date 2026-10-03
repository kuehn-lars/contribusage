---
type: decision
status: accepted
updated: 2026-10-03
aliases: [ADR-032]
tags: [app, core, ui, heatmap]
tracks: [App/Popover/GitHubSection.swift]
---
# ADR-032: One shared heatmap with a layer per source, Combined or Stacked, levels per source

- **Decided:** 2026-10-03 · **Spec:** FR-20, FR-48, FR-49, US-14, SPEC §7.7, §10.8, §11.4, T-5.16 · **Supersedes:** —

## Context
The heatmap belonged to the GitHub section (FR-20). With the popover becoming a set of blocks the user arranges (FR-44), the heatmap should show every source's daily activity: GitHub's contributions next to a provider's tokens. That raises three questions. First, how to draw several sources in one grid: the cells are about 10 pt wide, the number of providers will grow (T-5.17), and NFR-8 forbids conveying information by color alone. Second, how to put contributions (single digits) and tokens (millions) on one scale. Third, which colors: red was suggested for Claude Code, but red already means "critical" for limit bars (§11.4), and red next to green is the pair the most common color blindness confuses. Claude Code's `/stats` also draws a GitHub-style grid; it reads `~/.claude/stats-cache.json`, which is built from the same transcripts the provider already reads, is undocumented and versioned, and is updated with a lag of up to a day.

## Options
| Option | For | Against |
|---|---|---|
| Split cells: one stripe per source in each cell | One compact grid; sources compared per day at a glance | Stripes get thin from three sources on |
| Stacked grids: one per source, sharing the week columns | Readable for any number of sources | Taller popover |
| One neutral "any activity" grid plus a source picker | Compact | No comparison at a glance |
| Dot inside a cell for the second source | Compact | Works for exactly two sources |
| Sum all sources into one level | Simplest drawing | Contributions and tokens don't add up (§7.7) |
| Levels on one shared scale | One legend | Tokens dwarf contributions; GitHub would never leave level 1 |
| Read provider days from `stats-cache.json` | Might hold days already cleaned from transcripts | Second undocumented format; lags; same data otherwise |

## Decision
The heatmap is its own block with one layer per source that is on and in the heatmap. It offers two styles: **Combined** (default, split cells, one vertical stripe per layer in block order) and **Stacked** (one grid per layer). Each layer has its own levels: GitHub keeps its `contributionLevel`, so cells match the user's GitHub profile; a provider's layer uses the quartiles of its non-zero days in the shown range, the same kind of rule GitHub uses. Each provider declares a fixed `heatmapHue`. GitHub is green, Claude Code orange, and red is never a layer hue. The tooltip and VoiceOver read every layer's value for the day. Provider layers come from the activity data the provider already keeps, not from `stats-cache.json` (open as Q-8).

## Consequences
- A busy GitHub day and a busy Claude Code day both reach level 4: the levels compare days within a source, not sources with each other.
- A new provider needs a hue that isn't green or red; `HeatmapHue` lists the allowed ones.
- With three or more layers the Combined style gets narrow; Settings points to Stacked, and the style is never switched automatically.
- Revisit if Claude Code documents its stats data, or if a layer needs a different metric than total tokens (for example a provider without token counts, T-5.17).
