# Implementation Spec: Rich Tabs - Phase 2

**Contract**: ./contract.md
**Estimated Effort**: S

## Overview

Add Claude Code session detection by parsing the terminal title (OSC 0). Claude Code sets the terminal title to "Claude Code -- {session description}" when active. Parse this to populate `TabInfo.claudeCodeSession`.

## Technical Approach

Pure string parsing on `autoName` (which comes from `surfaceView.title`). A `TitleParser` module extracts structured information from terminal title strings. This is a simple, highly testable layer.

For multi-pane tabs, check all surface titles (not just the focused one) so the tab can indicate Claude Code activity in any pane.

## Feedback Strategy

**Inner-loop command**: `just test`
**Playground**: Test suite
**Why this approach**: Pure string parsing, tests are the feedback loop.

## File Changes

### New Files

| File Path | Purpose |
|-----------|---------|
| `Sources/Model/TitleParser.swift` | Parse terminal titles for Claude Code and other patterns |
| `Tests/TitleParserTests.swift` | Red/green tests for title parsing |

### Modified Files

| File Path | Changes |
|-----------|---------|
| `Sources/Model/TabInfo.swift` | Use TitleParser for claudeCodeSession derivation |

## Implementation Details

### TitleParser

```swift
// Sources/Model/TitleParser.swift
enum TitleParser {
    /// Extract Claude Code status from a terminal title.
    /// Returns nil if the title is not from Claude Code.
    /// Claude Code titles look like: "Claude Code -- fixing the BCI toggle"
    static func claudeCodeStatus(from title: String) -> ClaudeCodeStatus?

    /// Extract the "interesting" part of a terminal title.
    /// Strips common prefixes like shell names, login info.
    static func cleanTitle(_ title: String) -> String
}
```

### TabInfo integration

Update `TabInfo.from()` to call `TitleParser.claudeCodeStatus(from: tab.autoName)`. Returns a `ClaudeCodeStatus` with `.unknown` state (until we have a signal for working/waiting). For multi-pane tabs, also check titles from all surfaces (passed via an additional parameter or a titles array).

## Red/Green Tests

### TitleParserTests.swift

- `detectsClaudeCodeTitle` -- "Claude Code -- fixing BCI" -> ClaudeCodeStatus(sessionName: "fixing BCI", state: .unknown)
- `detectsClaudeCodeWithDashes` -- "Claude Code -- multi-word session name" -> session name extracted
- `returnsNilForShellTitle` -- "zsh" -> nil
- `returnsNilForEmptyTitle` -- "" -> nil
- `returnsNilForPlainCommand` -- "vim main.swift" -> nil
- `cleanTitleStripsShellPrefix` -- "zsh: ~/projects" -> "~/projects"

## Verification

- `just test` -- all title parsing tests pass (red first, then green)
- `just run` -- start Claude Code in a pane, tab shows session name
