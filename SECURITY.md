# Security policy

## Supported versions

Only the [latest release](https://github.com/kuehn-lars/contribusage/releases/latest) receives security fixes. Please check that a problem still occurs there, or on `main`, before you report it.

## Report a vulnerability

Please report security problems privately, not in a public issue:

1. Open the repository's [**Security** tab](https://github.com/kuehn-lars/contribusage/security).
2. Click **Report a vulnerability** and describe what you found: the version, the steps to reproduce, and what an attacker could do with it.

Only the maintainers see the report. You will get an answer as soon as possible, usually within a week. We'll work on a fix with you in the private advisory, and credit you when it is published, unless you prefer otherwise.

## What counts

contribusage promises a few things about safety (see [SPEC §2](SPEC.md#2-constitution-non-negotiable-principles) and [§14](SPEC.md#14-security-and-privacy)). Anything that breaks one of them is a vulnerability:

- The app reads a coding tool's credentials, such as Claude Code's credential file or Keychain items, or calls a vendor backend such as `api.anthropic.com` or `claude.ai`.
- The GitHub token leaves the Keychain other than in requests to `api.github.com`: into logs, files, diagnostics, the clipboard or another server.
- Prompt or message text from transcripts is kept, logged or sent anywhere.
- The app talks to any server other than `api.github.com`.
- The app runs anything other than what SPEC §14 allows (the resolved `claude` with the arguments in SPEC §8.1.1, and the PATH lookup), or input from a file or another process can change what it runs.
- The app reads files outside the roots SPEC §14 declares, or writes outside its own folder without asking you.
- A downloaded release is not the build CI made from the tagged commit.

## Verify a download

Every release DMG carries a build provenance attestation, signed by the CI run that built it. To check that a download is that build, run [GitHub CLI](https://cli.github.com) on it:

```bash
gh attestation verify contribusage-<version>.dmg --repo kuehn-lars/contribusage
```

A DMG that fails this check did not come from this repository's CI; please report it.

## Not a vulnerability

The app is ad-hoc signed and not notarized ([ADR-006](llm-wiki/decisions/0006-no-app-sandbox.md)), so Gatekeeper warns on first launch. That is expected and not a vulnerability.
