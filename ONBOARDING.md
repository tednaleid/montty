# Onboarding

Montty is a single-window macOS terminal app built on top of GhosttyKit (MIT).
It adds a vertical tab sidebar, splits, per-tab color coding, session restore,
Claude Code status indicators, and a Cmd+; surface-jump mode.

## Stack

- Language: Swift 5 (targets macOS 26 / Tahoe; Homebrew cask also pins `>= :tahoe`)
- UI: AppKit lifecycle with SwiftUI views; Ghostty's C API via `GhosttyKit.xcframework`
- Build: Xcode project generated from `project.yml` via `xcodegen`
- Task runner: Justfile (authoritative)
- Tests: Swift Testing (`import Testing`, `@Test`, `#expect`) -- not XCTest
- Lint: SwiftLint (strict); `Sources/Ghostty/` is excluded as upstream code

Note: `project.yml` still lists `MACOSX_DEPLOYMENT_TARGET: "14.0"`; the actual
shipped target is macOS 26. Update the manifest if/when that drift matters.

## Common commands

- Setup: `just setup` (inits submodules, builds GhosttyKit with zig 0.15.2)
- Generate: `just generate` (xcodegen)
- Build: `just build`
- Test: `just test`
- Lint: `just lint`
- Check: `just check` (test + lint + build; used by CI and pre-commit)
- Run: `just run` (foreground) or `just run-bg` (background, for scripting)
- Stop: `just stop` (skips the host Montty if you are sitting inside one)
- Clean: `just clean`
- Release: `just bump [version]`; `just retag <tag>` to re-trigger a release

Artifacts land in `/tmp/montty-build` (outside the project tree to avoid iCloud
resource forks that break codesign).

## Architecture

Three layers stacked on GhosttyKit's C API. `Sources/Ghostty/` is MIT-licensed
Swift bindings copied verbatim from the upstream submodule and resynced via
`just sync-bindings`; montty-local changes there are marked with `// MONTTY:`.
`Sources/Model/` holds the pure, testable model (tabs, split tree, jump labels,
hook events, git info). `Sources/View/` has the SwiftUI sidebar, minimap,
splits. `Sources/App/` holds the AppKit entry point (`main.swift`),
`AppDelegate`, menu builder, and the debug HTTP / hook socket servers.
`Sources/Persistence/` handles Codable session snapshots.

## Key paths

- `Sources/App/main.swift` -- entry point (AppKit `NSApplication.run()`)
- `Sources/App/AppDelegate.swift` -- app state, tab store, jump mode
- `Sources/App/DebugServer.swift` + `HookServer.swift` -- debug HTTP + Claude hook socket
- `Sources/Ghostty/` -- copied Ghostty Swift bindings (do not hand-edit without `// MONTTY:` markers)
- `Sources/Model/TabStore.swift`, `SplitTree.swift`, `JumpLabels.swift` -- core model
- `Sources/Persistence/SessionSnapshot.swift` -- JSON session format
- `project.yml` -- xcodegen input (incl. post-build zsh `claude()` wrapper injection)
- `Justfile` -- all build / release / inspect recipes
- `ghostty/` -- MIT-licensed Ghostty git submodule (source for `GhosttyKit.xcframework`)
- `Resources/Info.plist`, `Resources/montty.entitlements` -- app metadata and entitlements
- `Tests/` -- Swift Testing unit tests (run without a test host)
- `.github/workflows/` -- `ci.yml`, `release.yml`, `bump-ghostty.yml`

## How to run

```bash
just setup && just generate && just run
```

## Dig deeper

- [README.md](./README.md) -- user-facing feature list and install instructions
- [docs/debug-server.md](./docs/debug-server.md) -- full debug HTTP API (`just inspect-*`)
- [docs/spec/contract.md](./docs/spec/contract.md) -- project contract and phase plan
- [docs/spec/ghostty-binding-adaptation.md](./docs/spec/ghostty-binding-adaptation.md) -- how to re-apply MONTTY adaptations after `just sync-bindings`
- [docs/spec/progress.md](./docs/spec/progress.md) -- phase-by-phase progress log
- `.github/workflows/release.yml` -- DMG build, optional Developer ID signing/notarization, Homebrew cask update
