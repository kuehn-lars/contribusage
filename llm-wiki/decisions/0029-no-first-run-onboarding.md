---
type: decision
status: accepted
updated: 2026-10-03
aliases: [ADR-029]
tags: [app, ui, onboarding]
tracks: [App/Popover/SectionStateView.swift, App/Notifications]
---
# ADR-029: No first run onboarding

- **Decided:** 2026-10-03 · **Spec:** SPEC FR-37 (dropped), T-5.4 (dropped), US-6, §11.3, §16.5 · **Supersedes:** —

## Context
FR-37 asked for a first run onboarding in the popover: detect providers, offer the GitHub connection, ask for notification permission, offer launch at login, each step skippable. A card at the top of the popover was built for T-5.4 and judged unintuitive in review: the users are developers who configure a tool in its Settings, and the card was a second place for the same controls.

## Options
| Option | For | Against |
|---|---|---|
| Onboarding card in the popover (built, not merged) | One place that offers every first run choice | Duplicates Settings controls; a new setting (`onboardingDone`) and a wider FR-2 detection rule for a view seen once; pushes the data down in the first popovers |
| No onboarding | Nothing to build or maintain; every step is offered where the user meets it | Launch at login is offered only in Settings |

## Decision
No onboarding: FR-37 and T-5.4 are struck. Each step is already covered where it is needed: FR-2 enables the available providers on first run; a missing tool shows "not found" with Locate… and no transcripts show "No … sessions found" (SPEC §11.3); the GitHub section offers Connect GitHub without a token; macOS asks for notification permission before the first notification, which is delivered once allowed; launch at login is a toggle in Settings' General tab (FR-34).

## Consequences
- US-6 no longer offers launch at login on first run; it stays off until the user turns it on in Settings.
- The §16.5 "fresh macOS user" check relies on the popover's not configured states instead of an onboarding text.
- Revisit if the popover's states turn out not to explain a first run, for example once a provider needs a setup step the popover cannot offer.
