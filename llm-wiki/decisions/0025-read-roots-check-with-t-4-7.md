---
type: decision
status: accepted
updated: 2026-10-02
aliases: [ADR-025]
tags: [testing, conformance, activity]
tracks: [Packages/ContribusageKit/Tests/ContribusageTestSupport/ProviderConformance.swift]
---
# ADR-025: The declared-roots read check comes with T-4.7

- **Decided:** 2026-10-02 · **Spec:** SPEC §16.4, T-4.6, T-4.7 · **Supersedes:** —

## Context
SPEC §16.4 asked for a conformance check that a provider "reads no path outside its declared roots", through a fake file system that records accesses, built "with the first provider task that reads files". That is T-4.6, the Claude Code `ActivitySource`. Its reads go through three places: `TranscriptFiles.files(in:excludingProjectOf:)` lists the transcripts under the FR-22 roots, `IncrementalJSONLReader` reads only the URLs that listing returned, and `HistoryStore` reads the provider's own folder under the app root. A recording seam would have to replace `FileManager` enumeration, `FileHandle` with `fstat`, and `JSONStore`'s file access in the core.

## Options
| Option | For | Against |
|---|---|---|
| Build the file system seam in T-4.6 | The check exists as soon as a provider reads files | A core-wide seam over three readers, in a task about the activity source and its UI |
| Build it in T-4.7 | T-4.7 already rewires these reads for its 500 MB performance run and may change how they work (ADR-024); the seam is built once, around the final read path | Until then the boundary holds by construction only: every transcript read starts from `TranscriptFiles.files(in: roots)` |

## Decision
The seam and the check are part of T-4.7. Until then `ProviderConformance` states that it does not check reads.

## Consequences
- SPEC §16.4 and T-4.7 name the task; the conformance suite's doc comment points to T-4.7.
- A provider added before T-4.7 is reviewed for its reads by hand.
- Built in T-4.7: the `FileReading` seam (SPEC §10.6) runs through the three read paths, each taking it as a required parameter, so a new read path cannot skip it; `ProviderConformance.check` takes a recording `FakeFileReader` and the declared `readRoots` and fails on any read outside them, comparing whole path components. `conformanceSuiteRejectsAReadOutsideTheRoots` keeps the check able to fail.
