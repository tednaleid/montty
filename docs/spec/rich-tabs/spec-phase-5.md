# Implementation Spec: Rich Tabs - Phase 5

**Contract**: ./contract.md
**Estimated Effort**: M (5a), L (5b)

## Overview

Add Claude Code activity indicators to the tab minimap so users can see at a glance which panes are running Claude Code and whether Claude needs attention.

Phase 5a detects Claude Code presence from the terminal title (OSC 0) and shows a visual indicator. Phase 5b adds hook-based state detection to distinguish working from waiting.

## Research: Terminal Title Signals

Claude Code sets the terminal title via OSC 0:
- On startup: title = `✳ Claude Code`
- When working on a task: title = `✳ <task description>` (e.g., `✳ Determine user name and favorite color`)
- The `✳` prefix is present whenever Claude Code is active
- The title does NOT change between working and waiting states -- it stays the same whether Claude is processing or blocked on a user prompt

Conclusion: title parsing can detect Claude Code **presence** but not **state**.

## Phase 5a: Title-Based Detection

### Technical Approach

Detect Claude Code presence per-surface by checking for the `✳` prefix in terminal titles. Currently, `tab.autoName` only tracks the last surface's title update. Phase 5a adds per-surface title tracking so we know which specific pane is running Claude Code.

### File Changes

| File | Changes |
|------|---------|
| `Sources/Model/TitleParser.swift` | Update to detect `✳` prefix instead of `Claude Code -- ` |
| `Sources/Model/Tab.swift` | Add `surfaceTitles: [UUID: String]` dictionary |
| `Sources/Model/TabInfo.swift` | Accept surface titles, compute per-pane Claude status |
| `Sources/Model/SplitMinimap.swift` | Add `claudeCode: ClaudeCodeStatus?` to MinimapPane |
| `Sources/App/AppDelegate.swift` | Store per-surface titles in Tab instead of overwriting autoName |
| `Sources/View/MinimapView.swift` | Render Claude Code indicator on panes |
| `Tests/TitleParserTests.swift` | Update for new title format |
| `Tests/SplitMinimapTests.swift` | Tests for claudeCode on MinimapPane |

### TitleParser Update

```swift
enum TitleParser {
    /// Detect Claude Code from terminal title.
    /// Claude Code titles start with "✳" (e.g., "✳ Claude Code", "✳ Fix the auth bug")
    static func claudeCodeStatus(from title: String) -> ClaudeCodeStatus?
}
```

The `✳` prefix is the signal. Extract the task description (everything after `✳ `). Return `ClaudeCodeStatus(sessionName: taskDescription, state: .unknown)`.

### Per-Surface Title Tracking

Currently `observeSurface` writes every surface's title to `tab.autoName` (one value per tab). Change to store per-surface titles:

```swift
// Tab.swift
var surfaceTitles: [UUID: String] = [:]

// AppDelegate.observeSurface()
surfaceView.$title
    .receive(on: DispatchQueue.main)
    .sink { [weak tab] title in
        tab?.autoName = title
        tab?.surfaceTitles[surfaceView.id] = title
    }
```

### MinimapPane Claude Code Field

```swift
struct MinimapPane: Equatable {
    let leafID: UUID
    let rect: MinimapRect
    let isFocused: Bool
    let claudeCode: ClaudeCodeStatus?  // nil if no Claude Code in this pane
}
```

`SplitMinimap.from()` accepts a `surfaceTitles: [UUID: String]` parameter. For each leaf, it looks up the surface title and runs `TitleParser.claudeCodeStatus()` to populate the field.

### Visual Indicator

On minimap panes where `claudeCode != nil`, render a bold orange `*` character. In Phase 5a this is static (presence only).

### Red/Green Tests

- `detectsClaudeCodeFromStarPrefix` -- `"✳ Claude Code"` -> detected
- `detectsClaudeCodeTaskDescription` -- `"✳ Fix the auth bug"` -> sessionName = "Fix the auth bug"
- `returnsNilWithoutStar` -- `"zsh"` -> nil
- `minimapPaneHasClaudeCodeFromTitle` -- surface with `✳` title gets claudeCode set on its MinimapPane

---

## Phase 5b: Hook-Based State Detection

### Technical Approach

Claude Code supports a `--settings` flag that merges additively with the user's own settings.json (user hooks are preserved). montty's shell integration defines a `claude()` shell function that wraps the real `claude` binary, injecting `--settings` with hook definitions that call back to montty.

### Environment Variables (per-surface)

Set via `SurfaceConfiguration.environmentVariables` when spawning each surface:

- `MONTTY_SURFACE_ID` -- UUID of the surface, used to route hook callbacks to the correct pane
- `MONTTY_PORT` -- HTTP port where montty listens for hook callbacks (debug server port in dev, dedicated port in release)

### Shell Integration

Add a `claude()` function to montty's shell integration that intercepts `claude` invocations:

```bash
claude() {
    if [[ -n "$MONTTY_SURFACE_ID" && -n "$MONTTY_PORT" ]]; then
        # Inject hooks that call back to montty
        command claude --settings '{"hooks": {
            "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "curl -sf -X POST http://localhost:'"$MONTTY_PORT"'/claude-hook -d prompt-submit -H X-Surface:'"$MONTTY_SURFACE_ID"'"}]}],
            "Notification": [{"hooks": [{"type": "command", "command": "curl -sf -X POST http://localhost:'"$MONTTY_PORT"'/claude-hook -d notification -H X-Surface:'"$MONTTY_SURFACE_ID"'"}]}],
            "Stop": [{"hooks": [{"type": "command", "command": "curl -sf -X POST http://localhost:'"$MONTTY_PORT"'/claude-hook -d stop -H X-Surface:'"$MONTTY_SURFACE_ID"'"}]}]
        }}' "$@"
    else
        command claude "$@"
    fi
}
```

### Hook Endpoint

Add a `POST /claude-hook` endpoint to the debug server (and eventually a production HTTP server):

- Reads `X-Surface` header to identify the surface
- Reads body for the hook type (`prompt-submit`, `notification`, `stop`)
- Updates per-surface Claude status on the Tab model

### State Machine

```
           prompt-submit
  idle ──────────────────> working
   ^                         |
   |         stop            |
   +─────────────────────────+
   ^                         |
   |       notification      |
   |    +─────────────────> waiting
   |    |                    |
   +────+   prompt-submit    |
        <────────────────────+
```

- `prompt-submit` -> working (Claude is processing)
- `notification` -> waiting (Claude needs user input)
- `stop` -> idle (Claude finished its turn)

### Visual Indicators

On minimap panes:
- **Working**: bold orange `*` that animates through star-like characters (`*`, `✶`, `✻`, `✳`, `✢`, `·`)
- **Waiting**: blinking `*?` in orange (needs attention)
- **Idle**: no indicator (or dimmed `*`)

### Red/Green Tests

- `hookSetsWorkingState` -- prompt-submit hook -> state = .working
- `hookSetsWaitingState` -- notification hook -> state = .waiting
- `hookSetsIdleState` -- stop hook -> state = .idle
- `hookRoutesToCorrectSurface` -- surface ID routes to the right pane

## Verification

### Phase 5a
- `just test` -- updated TitleParser tests pass
- `just run` -- start Claude Code in a pane, orange `*` appears on that pane's minimap

### Phase 5b
- `just test` -- hook state machine tests pass
- `just run` -- start Claude Code, see animated `*` while working, blinking `*?` when Claude asks a question
