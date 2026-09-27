---
type: module
status: planned
updated: 2026-09-28
tracks: []
tags: [core, architecture]
---
# ContribusageCore

The provider-neutral heart of the package: models, provider protocols and registry, the refresh scheduler, notification planning, generic activity infrastructure, persistence and the support seams (time, processes, HTTP, Keychain, file events, paths). It knows no concrete provider and nothing about GitHub (NFR-17).

## Spec
- **Sections:** SPEC §7 (provider model), §9 (architecture), §10.1 to §10.4, §10.6, §10.7 (types, seams, persistence), §12 (refresh policy), §13 (error handling)
- **Requirements:** FR-1 to FR-5, FR-10, FR-13 to FR-15, FR-26, FR-29; NFR-4, NFR-5, NFR-14, NFR-17, NFR-18
- **Tasks:** T-1.4 to T-1.6, T-2.4, T-2.6, T-3.1 (Keychain `SecretStore`), T-4.3, T-4.4, T-5.1 (planner), T-5.6
- **Path:** `Packages/ContribusageKit/Sources/ContribusageCore/`

## Depends on
Nothing inside the package. Every other target depends on it.

## Related
[[decisions/0004-logic-in-contribusagekit-package]] · [[decisions/0005-json-file-persistence]] · [[decisions/0010-provider-abstraction-from-day-one]] · [[modules/test-support]]
