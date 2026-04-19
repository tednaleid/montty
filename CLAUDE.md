# montty

For project orientation (stack, build/test commands, architecture, entry points), see [ONBOARDING.md](./ONBOARDING.md).

Implementation specs are in `docs/spec/`. Start with `contract.md` for the overview.

## Rules

- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) -- not XCTest.
- Red/green testing: write a failing test first, then make it pass. Tests must verify observable runtime behavior, not source text or file contents.
- Keep model logic pure and testable. Tab ordering, split tree operations, session persistence, and color assignment should all be unit-testable without AppKit or SwiftUI.
- Simple purpose-built mocks. No heavy mocking frameworks.
- Tests should run fast (target: full suite under 5 seconds).
- `Sources/Ghostty/` is upstream code copied from the Ghostty submodule. Minimize modifications to make upstream syncs easier. Mark every montty-local change there with a `// MONTTY:` comment. SwiftLint excludes this directory.
- Ghostty's C API calls must happen on the main actor.
- Single window app. No multi-window support.
- Tab state (names, colors, positions) is persisted automatically in a session JSON file. No user-facing config file for tab settings. Terminal theming comes from `~/.config/ghostty/config`.
