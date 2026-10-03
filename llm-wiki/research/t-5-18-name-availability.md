---
type: research
status: answered
updated: 2026-10-04
tracks: []
tags: [research, naming]
---
# T-5.18: Name availability

- **Spec:** SPEC §17 T-5.18, §19.1 Q-6, §2.3 · **Blocks:** nothing · **Answered:** 2026-10-04

## Question
Is the name "contribusage" ([[decisions/0011-product-name-contribusage]]) free to use for a public release: no app, package, domain or trademark under the same or a confusingly similar name (Q-6, name part)?

## Method
All checks on 2026-10-04, for the exact string and, where the source supports it, near variants (`contribus*`, `contrib*usage`).

| Source | How |
|---|---|
| Mac App Store, iOS App Store (US, DE) | iTunes Search API, `entity=macSoftware` and `software` |
| Domains `.com`, `.dev`, `.app`, `.io`, `.org` | `whois`; RDAP at the Google registry for `.dev` and `.app` |
| GitHub | `gh search repos`, user and organization search |
| Package registries | Homebrew casks, npm, PyPI, crates.io: HTTP status of the package URL |
| Web | Web search for `"contribusage"` and `contribusage trademark` |
| USPTO | Trademark search backend, word mark and pseudo text, exact and near variants |
| TMview (EUIPO, DPMA, other EU offices, WIPO Madrid designations) | Searched by hand in the browser; its API is not reachable from a script |

## Findings
- **App Stores:** no app named "contribusage" on the Mac App Store; the four iOS results for the term are unrelated names.
- **Domains:** all five are unregistered.
- **GitHub:** the only repository is this project; no user or organization of that name.
- **Registries:** no Homebrew cask, npm, PyPI or crates.io package.
- **Web:** no use of the word; results only match "contrib" and "usage" separately.
- **Trademarks:** USPTO has no live or dead mark for the string or its near variants; TMview has no result.

## Outcome
The name is free: [[decisions/0011-product-name-contribusage]] stands. SPEC §17 T-5.18 ticked, §19.1 Q-6 answered for the name; the icon stays with T-6.7. Claiming the domains, a Homebrew cask or the GitHub organization is not part of the contract and is left to the release (T-6.7). The check is a snapshot: re-run the web and trademark searches if the release slips far past this date.
