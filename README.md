# contribusage
A native macOS menu bar app for Apple Silicon that shows the usage of your AI coding tools and your GitHub contributions at a glance.

**Status:** foundation. The app skeleton builds and CI runs; nothing to install yet.

## Build
Needs an Apple Silicon Mac with Xcode 26 or later; the app itself runs on macOS 14 and later.

```bash
swift test --package-path Packages/ContribusageKit
xcodebuild -project Contribusage.xcodeproj -scheme Contribusage -configuration Debug -derivedDataPath .build/xcode build
open .build/xcode/Build/Products/Debug/contribusage.app
```

More commands in [SPEC §15.6](SPEC.md#156-everyday-commands).

## How this repository works
contribusage is built spec-first, with coding agents, and everything they need lives in the repository:

- [`SPEC.md`](SPEC.md) is the contract: requirements with stable IDs, the task plan, open research.
- [`llm-wiki/`](llm-wiki/) is the project's memory: an [Obsidian](https://obsidian.md) vault the agents maintain, following Andrej Karpathy's LLM-wiki pattern. It holds a page per module, the architecture decisions, research findings and a change log. Start at [`overview.md`](llm-wiki/overview.md), or open the folder as a vault for the graph view.
- [`AGENTS.md`](AGENTS.md) is the protocol every agent follows: orient in the vault, work against the spec, record what changed.
