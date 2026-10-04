# Contributing to contribusage

Thanks for your interest! Bug reports, ideas, fixes, docs and features are all welcome. You don't need to ask before you start: open an issue or a pull request, whichever fits.

## Report a bug or suggest an idea

[Open an issue](https://github.com/kuehn-lars/contribusage/issues/new) and describe what you expected and what happened. For bugs, Settings → Advanced → **Copy Diagnostics** gives us the versions and each provider's state; it never contains a token, but give it a quick read before you paste it.

If the limits suddenly disappear after a Claude Code update, its `/usage` output has probably changed. The output of `claude -p "/usage"`, with anything personal removed, helps a lot.

Found a security problem? Please report it privately under **Security → Report a vulnerability** instead of in an issue.

## Build and run

You need a Mac with Apple Silicon and Xcode 26 or later. To run the app against real data, also [Claude Code](https://code.claude.com), logged in.

```bash
git clone https://github.com/<you>/contribusage.git && cd contribusage
swift test --package-path Packages/ContribusageKit -Xswiftc -warnings-as-errors
xcodebuild -project Contribusage.xcodeproj -scheme Contribusage -configuration Debug -derivedDataPath .build/xcode build
open .build/xcode/Build/Products/Debug/contribusage.app
```

Or open `Contribusage.xcodeproj` in Xcode and run the `Contribusage` scheme. Before you push, format the code and run the tests:

```bash
swift format format --in-place -r App Packages
swift test --package-path Packages/ContribusageKit -Xswiftc -warnings-as-errors
```

## Find your way around

- `App/` is the SwiftUI app: views and wiring.
- `Packages/ContribusageKit/` holds the logic and its tests: `ContribusageCore` (models, scheduling, storage), `ContribusageClaudeCode`, `ContribusageGitHub`, and `ContribusageTestSupport` (fakes for tests).
- [`SPEC.md`](SPEC.md) describes what the app should do, with numbered requirements and a task list in §17. It's long; search it rather than reading it whole.
- [`llm-wiki/`](llm-wiki/) explains how it's built and why: a page per module, the design decisions, research notes. [`overview.md`](llm-wiki/overview.md) is a good start.

## A few rules

These keep the app safe and trustworthy, so pull requests that break them can't be merged:

- **Hands off other tools' credentials.** The app never reads Claude Code's login and never calls `api.anthropic.com` or `claude.ai`; it only runs the `claude` CLI. [SPEC §2.1](SPEC.md#21-why-principle-2-matters-claude-code) explains why.
- **No telemetry**, and the GitHub token stays in the Keychain and out of logs.
- **No personal data in the repository:** no tokens, real transcripts or unscrubbed tool output in fixtures, issues or docs.
- **Builds stay clean:** Swift 6, zero warnings, Apple Silicon only.

## Pull requests

- Branch from `main` and open the pull request against it. Draft pull requests are welcome if you want early feedback.
- Add or update tests for the logic you change. New tests use Swift Testing (`@Test`, `#expect`).
- Describe what you changed and how you tested it; for UI changes, a screenshot helps.
- If your change completes a task from SPEC §17, tick its box; if it changes how something should behave, update the spec too.

CI runs the tests, the format check, the app build and a check of the wiki. Two things it may ask of you:

- **New or changed text in the app** needs an entry in its String Catalog and a German translation. Build in Xcode to add the entry; if you don't speak German, say so and we'll translate it.
- **The wiki check** may flag a page under `llm-wiki/` as stale because it describes code you changed. Update the page, or just its `updated:` date if it still holds. Not sure? Leave it, and we'll take care of it before merging.

## Using a coding agent

Go ahead, the project is built that way. Agents find their instructions in [`AGENTS.md`](AGENTS.md) (Claude Code reads it through `CLAUDE.md`), including how to keep the wiki up to date. Review what your agent writes as if you had typed it yourself.

## Bigger changes

Support for another AI coding tool starts in the spec: it has to pass the provider gate in [SPEC §2.4](SPEC.md#24-provider-gate), which checks that the tool's data can be read through official interfaces only. Opening an issue first saves you work here, as it does for anything that changes the design.

## License

Contributions are released under the project's [MIT License](LICENSE).
