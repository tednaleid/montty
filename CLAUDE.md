# montty

A macOS terminal app built on GhosttyKit (MIT licensed) with vertical tabs.

## Project specs

Implementation specs are in `docs/spec/`. Start with `contract.md` for the overview.

## Build

```bash
just setup      # init submodules, build GhosttyKit
just build      # compile the app
just run        # build and launch
just test       # run unit tests
just lint       # run SwiftLint
```

## Debug server

Debug builds include an HTTP server on `localhost:9876` for programmatic terminal interaction. See `docs/debug-server.md` for full API documentation.

```bash
just run                            # launches app with debug server
just inspect-surfaces               # list terminal surfaces
just inspect-type "echo hello"      # type text
just inspect-key return             # send key event
just inspect-screen                 # read terminal text
just inspect-screenshot             # save PNG to .llm/inspect/
just inspect-state                  # get terminal metadata
```

## Testing philosophy

- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) -- not XCTest.
- Red/green testing: write a failing test first, then make it pass. Tests must verify observable runtime behavior, not source text or file contents.
- Keep model logic pure and testable. Tab ordering, split tree operations, session persistence, and color assignment should all be unit-testable without AppKit or SwiftUI.
- Simple purpose-built mocks. No heavy mocking frameworks.
- Tests should run fast (target: full suite under 5 seconds).

## Architecture

- `Sources/Ghostty/` contains copied MIT-licensed Swift bindings from Ghostty. Minimize modifications to make upstream syncs easier. Mark all changes with `// MONTTY:` comments.
- `Sources/Model/` contains montty's own data model (tabs, splits, session snapshots). This is where most testable logic lives.
- `Sources/View/` contains SwiftUI views.
- `Sources/App/` contains the app entry point and AppDelegate.
- The Ghostty submodule is at `ghostty/` (MIT licensed). Swift bindings are copied from `ghostty/macos/Sources/Ghostty/`.

## Conventions

- SwiftLint enforces code style. `Sources/Ghostty/` is excluded from linting (upstream code).
- Ghostty's C API calls must happen on the main actor.
- Single window app. No multi-window support.
- Tab state (names, colors, positions) is persisted automatically in a session JSON file. No user-facing config file for tab settings. Terminal theming comes from `~/.config/ghostty/config`.
