---
name: test-app
description: >
  Interactive testing of the running montty app via its debug HTTP server.
  Use this skill whenever you need to verify app behavior yourself -- after
  implementing a feature, fixing a bug, or when the user asks you to "try it",
  "test it", "check if it works", "run the app and see", or "exercise it".
  Also use when debugging session persistence, tab state, split layouts, or
  any visual/behavioral issue that can't be verified by unit tests alone.
---

# Testing montty via the Debug Server

montty includes a debug HTTP server (localhost:9876) in Debug builds that lets
you interact with the running app programmatically. This is your way to "use"
the app -- type commands, read terminal output, take screenshots, create tabs
and splits, and verify behavior.

## Quick Reference

| Recipe | What it does |
|--------|-------------|
| `just build` | Compile the app |
| `just run-bg` | Build and launch in background |
| `just stop` | Quit gracefully (triggers session save) |
| `just inspect-surfaces` | List all terminal surfaces (tabs/panes) |
| `just inspect-type "text"` | Type text into focused terminal |
| `just inspect-key return` | Send a key event |
| `just inspect-screen` | Read visible terminal text |
| `just inspect-screenshot` | Save PNG to .llm/inspect/ |
| `just inspect-state` | Get terminal metadata (title, pwd, size) |
| `just inspect-action action` | Trigger a Ghostty keybind action |

All `inspect-*` recipes accept an optional `surface=UUID` parameter to target
a specific surface instead of the focused one.

## Lifecycle

### Starting the app

```bash
just run-bg
```

This builds, launches in background, and waits 2 seconds for startup. The
debug server is ready when you can successfully call `just inspect-surfaces`.

If the app is already running, `just stop` it first -- only one instance can
run at a time.

### Stopping the app

```bash
just stop
```

This sends a graceful quit via osascript. The app saves its session on quit,
so always use `just stop` rather than killing the process if you care about
session state.

### Full restart cycle

```bash
just stop && sleep 1 && just run-bg
```

The sleep ensures the previous instance fully terminates before relaunching.

## Working with Surfaces

Every terminal pane is a "surface" with a UUID. Tabs can have one or more
surfaces (splits). Use `just inspect-surfaces` to see them all:

```bash
just inspect-surfaces
```

Returns JSON array with id, title, pwd, focused status, and size for each
surface. The `focused` field tells you which surface receives input by default.

### Targeting a specific surface

Pass the UUID to any inspect command:

```bash
just inspect-type "ls" surface=A1B2C3D4-...
just inspect-key return surface=A1B2C3D4-...
just inspect-screen surface=A1B2C3D4-...
```

### Creating tabs and splits

Use the action endpoint to trigger Ghostty keybind actions:

```bash
just inspect-action new_tab
just inspect-action new_split:right
just inspect-action new_split:down
just inspect-action "goto_tab:1"
just inspect-action "goto_tab:2"
```

## Common Testing Workflows

### Verify a command runs correctly

```bash
just inspect-type "echo hello"
just inspect-key return
sleep 0.5
just inspect-screen
```

The sleep gives the shell time to execute and render output. For commands
that take longer, increase the delay.

### Change directory in a pane

```bash
just inspect-type "cd /tmp"
just inspect-key return
sleep 0.5
just inspect-state    # verify pwd changed
```

### Take a screenshot for visual verification

```bash
just inspect-screenshot
```

Screenshots are saved to `.llm/inspect/` with timestamps. Read the
returned path to view the screenshot.

### Test session persistence

This is the pattern for verifying that state survives a quit/relaunch cycle:

1. Set up state (create tabs, change directories, rename tabs, etc.)
2. Wait for auto-save (8 seconds) or trigger a manual quit
3. Optionally inspect the session file before restarting
4. Restart and verify state was restored

```bash
# 1. Set up state
just inspect-type "cd /tmp"
just inspect-key return
sleep 0.5

# 2. Quit (triggers session save)
just stop
sleep 1

# 3. Inspect saved session (optional, for debugging)
cat ~/Library/Application\ Support/montty/session.json | jq .

# 4. Relaunch and verify
just run-bg
just inspect-state    # check pwd is /tmp
just inspect-surfaces # check all tabs restored
```

### Debug session persistence issues

The session file is at:
```
~/Library/Application Support/montty/session.json
```

Read it with jq to inspect saved state:

```bash
# See all tabs and their saved directories
cat ~/Library/Application\ Support/montty/session.json | jq '.tabs[] | {name, leafDirectories}'

# See the full snapshot
cat ~/Library/Application\ Support/montty/session.json | jq .
```

Key fields in session.json:
- `tabs[].name` -- user-set tab name
- `tabs[].color` -- tab color
- `tabs[].splitLayout` -- the split tree structure
- `tabs[].leafDirectories` -- map of leaf UUID to saved working directory
- `tabs[].focusedLeafID` -- which pane had focus

## Tips

- Always `just stop` before `just run-bg` to avoid port conflicts.
- After typing a command, send `just inspect-key return` to execute it.
- Use `sleep 0.5` between typing and reading output to let the shell respond.
- Use `just inspect-surfaces` liberally to understand which surfaces exist
  and which is focused.
- Screenshots are the best way to verify visual layout (splits, tab sidebar).
- The session auto-saves every 8 seconds, but `just stop` forces an immediate
  save, which is more reliable for testing persistence.
