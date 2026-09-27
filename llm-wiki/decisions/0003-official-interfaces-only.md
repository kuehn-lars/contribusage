---
type: decision
status: accepted
updated: 2026-09-28
aliases: [ADR-003]
tags: [compliance, security, providers]
---
# ADR-003: Official interfaces only, never another tool's credentials

- **Decided:** 2026-09-28 · **Spec:** SPEC §2 (principles 1 and 2), §2.1, §2.4, §14 · **Supersedes:** —

## Context
Many community tools read Claude Code's OAuth token and call an undocumented usage endpoint. Anthropic's legal and compliance page reserves OAuth sign-in for Claude Code and Anthropic's own apps and prohibits intermediating Claude.ai credentials (summary in SPEC §2.1). Breaking that puts the user's account at risk.

## Options
| Option | For | Against |
|---|---|---|
| OAuth token plus the undocumented usage endpoint | Exact numbers, no process to start | Violates the terms; endpoint can change without notice |
| Scraping claude.ai | No CLI dependency | Violates the terms; fragile |
| The official CLI and files the tool writes on this Mac | Ordinary use of the tool as the user; within the terms | Text output without a format guarantee; some data may be unavailable |

## Decision
The app never reads, stores or forwards any tool's credentials and never calls a tool vendor's backend. Data comes only from official, unmodified interfaces and local files. The rule applies to every future provider through the provider gate (SPEC §2.4).

## Consequences
- A capability that needs credentials or undocumented endpoints is not built, even if it means a provider ships partially or not at all.
- Provider targets receive no `HTTPTransport`; the app itself talks only to `api.github.com` (NFR-13).
- Every PR touching a provider target is reviewed against this rule (SPEC §14).
