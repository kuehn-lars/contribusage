---
type: decision
status: accepted
updated: 2026-10-03
aliases: [ADR-034]
tags: [popover, layout, settings]
tracks: [Packages/ContribusageKit/Sources/ContribusageCore/Models/PopoverLayout.swift, App/Settings/PopoverTab.swift]
---
# ADR-034: A provider group's sections are reordered within the group

- **Decided:** 2026-10-03 · **Spec:** FR-31, FR-44, FR-45, US-13, SPEC §10.8, §11.6 · **Supersedes:** FR-44's "their order inside the group is fixed"

## Context
T-5.15 built the Popover tab with blocks that move by drag and sections that only show or hide, as FR-44 had it. In use, the fixed order was the first thing missing: a group's sections look like rows of their own, and nothing tells why they cannot move.

## Options
| Option | For | Against |
|---|---|---|
| Keep the fixed order | No new state | The rows invite a drag that does nothing |
| Reorder within the group | Same gesture as blocks; one more map in the layout | A saved layout without the new key decodes as the default once |
| Sections as free blocks across groups | Most freedom | A section without its provider's header loses its context; the demand rule and Copy would need per-section blocks |

## Decision
`PopoverLayout.sectionOrder` keeps a section order per provider; `sections(of:)` fills in missing sections in default order (limits, activity, insights), as `arranged(registered:)` does for blocks, and `move(_:to:of:)` moves a section within its group only. The popover and Copy statistics follow `shownSections(of:)`.

## Consequences
- Blocks and sections share one "saved order plus missing ones" rule and one "take the target's place" move in `PopoverLayout.swift`.
- A section's drag payload names its provider, so a drop in another group or on a block does nothing.
- Layouts saved before this change lack `sectionOrder` and decode as the default layout once; no release had shipped them.
- Layer order in the shared heatmap is block order, so dragging a block also moves its stripe or grid (T-5.16, FR-49).
