# Debug Server

montty includes a debug-only HTTP server for programmatic terminal interaction. It listens on `localhost:9876` and is only compiled into Debug builds (`#if DEBUG`). It is never included in release builds.

This enables automated testing, Claude-driven interaction, and scripted terminal workflows -- like Playwright for terminals.

## Starting the server

```bash
just run
```

The console will print `[DebugServer] Listening on localhost:9876` when ready.

## Endpoints

All endpoints that interact with a surface accept an optional `?surface=<uuid>` query parameter. If omitted, the focused surface is used. Use `GET /surfaces` to discover available surface UUIDs.

### GET /surfaces

List all terminal surfaces.

```bash
curl -s localhost:9876/surfaces | jq .
```

Response:
```json
[
  {
    "id": "A1B2C3D4-...",
    "leaf_id": "E5F6A7B8-...",
    "montty_surface_id": "F1E2D3C4-...",
    "tab_id": "C9D0E1F2-...",
    "tab_name": "montty",
    "tab_position": 0,
    "tab_color": "brightRed",
    "active": true,
    "focused_in_tab": true,
    "focused": true,
    "split_count": 1,
    "title": "zsh",
    "pwd": "/Users/ted/montty",
    "window_id": "D4C3B2A1-...",
    "window_is_key": true,
    "window_frame": {"x": 661, "y": 39, "width": 1400, "height": 900},
    "size": {"rows": 24, "cols": 80, "width_px": 1200, "height_px": 800},
    "color": {
      "effective": ["neutralBright", "brightRed"],
      "source": "git",
      "surface_override": null,
      "tab_override": null,
      "repo_override": null
    }
  }
]
```

This surface has no color override at any scope, so `git` wins and
`effective` is the repo's own two-stop signature. `tab_color` matches
`effective`'s trailing stop, `brightRed`, because this is the tab's focused
surface. A surface with its own override would instead show, for example,
`"source": "surface"` and `"effective"` equal to `"surface_override"`
exactly -- `resolvedPaneTint` returns a winning override verbatim, with no
merging, so a scope's `effective` and its own override field can never
disagree.

`color` describes what is actually painted for that specific surface, not the
tab as a whole -- two panes in the same split can report different `color`
objects. `effective` is the full ordered stop list as rendered (palette name
or `#rrggbb`), always an array even when it is a single stop. `source` names
the scope that won -- `surface`, `tab`, `repo`, `git`, or `none` -- checked in
that precedence order. `surface_override`, `tab_override`, and
`repo_override` report the raw override for each scope, or `null` when that
scope has nothing set; `repo_override` also carries the repo/worktree
`identity` the override is keyed on. `tab_color` at the top level is the
older, tab-wide field kept for existing callers -- it always matches the
`color.effective` of the tab's currently focused surface.

`focused_in_tab` is montty's model state: which pane a given tab will focus when that tab becomes active. It can be true for several surfaces at once, one per tab. `focused` is what libghostty believes: it is true for at most one surface across the entire app, and false for every surface while the montty window is not key. The `directory_name`, `git`, and `activity` keys appear only when they apply to the surface; `color` is always present.

`id` is montty's own internal handle for the surface -- not addressable over the socket. `montty_surface_id` is the value exported to each pane as `MONTTY_SURFACE_ID`; it is what the control and hook socket addresses (`montty-hook.sock` in the system temporary directory, or wherever `MONTTY_SOCKET` points), and what a shell inside the pane can read to identify itself. It is `null` in the unlikely case a leaf has no assigned id. Use `montty_surface_id`, not `id`, when scripting requests against the socket.

`window_id` is the window the surface's tab belongs to; every surface in the same window reports the same `window_frame` and `window_id`. `window_frame` is that window's on-screen position and size in screen coordinates, in the same `x`/`y`/`width`/`height` shape the session file stores. `window_is_key` marks the window that receives commands -- new tabs, keybind actions, and other window-scoped requests land there -- and is true for every surface in that window. It names the window that most recently held keyboard focus, and stays set on that window while montty itself is not the frontmost application; it does not clear when focus moves away. For a surface's actual keyboard focus, use `focused` instead -- the two fields can disagree whenever montty is in the background, since `window_is_key` keeps pointing at the last-active window while every surface's `focused` drops to false.

### POST /type

Send text to the terminal as if typed. Does not include a trailing newline -- use `/key` with `return` to execute.

```bash
curl -s -X POST localhost:9876/type -d 'echo hello'
```

### POST /key

Send a special key or key combination.

```bash
curl -s -X POST localhost:9876/key -d 'return'
curl -s -X POST localhost:9876/key -d 'ctrl+c'
curl -s -X POST localhost:9876/key -d 'tab'
```

Supported keys: `return`/`enter`, `tab`, `space`, `escape`/`esc`, `backspace`/`delete`, `ctrl+c`, `ctrl+d`, `ctrl+z`, `ctrl+l`, `ctrl+a`, `ctrl+e`, `ctrl+k`, `ctrl+u`, `ctrl+w`, `ctrl+r`.

### GET /screen

Read the visible terminal text.

```bash
curl -s localhost:9876/screen | jq .
```

Response:
```json
{
  "text": "$ echo hello\nhello\n$ ",
  "rows": 24,
  "cols": 80
}
```

### GET /session

The session snapshot montty would write right now -- the same value
`SessionStore` serializes to `session.json`, with no intermediate re-encoding.
Answers "what would we save" without quitting the app to find out.

```bash
curl -s localhost:9876/session | jq .
```

Response:
```json
{
  "version": 4,
  "surfaceTintEnabled": true,
  "keyWindowID": "D4C3B2A1-...",
  "repoColorOverrides": {},
  "windows": [
    {
      "windowID": "D4C3B2A1-...",
      "frame": {"x": 661, "y": 39, "width": 1400, "height": 900},
      "sidebarWidth": 200,
      "activeTabID": "C9D0E1F2-...",
      "tabs": [
        {
          "tabID": "C9D0E1F2-...",
          "name": "montty",
          "position": 0,
          "focusedLeafID": "E5F6A7B8-...",
          "splitLayout": {
            "type": "leaf",
            "leaf": {"id": "E5F6A7B8-...", "surfaceID": "F1E2D3C4-..."}
          },
          "leafDirectories": ["E5F6A7B8-...", "/Users/ted/montty"],
          "leafColorOverrides": []
        }
      ]
    }
  ]
}
```

`leafDirectories` and `leafColorOverrides` are keyed by leaf ID
(`[UUID: String]` and `[UUID: PaneTint]`), which `JSONEncoder` renders as a
flat array of alternating keys and values rather than an object, since a
`UUID` key isn't a valid JSON object key.

### GET /screenshot

Capture the terminal view as a PNG image. Raises the window that owns the
requested surface before capturing, so a surface in a background window is
captured un-occluded rather than whatever window happens to be in front.

Without a `surface` parameter it captures the window macOS reports as main or
key, falling back to the first visible window. While montty is not the frontmost
application there is no main or key window, so that fallback picks an arbitrary
one. Name a surface when it matters which window you get.

```bash
curl -s localhost:9876/screenshot -o screenshot.png
```

### GET /state

Get terminal metadata.

```bash
curl -s localhost:9876/state | jq .
```

Response:
```json
{
  "id": "A1B2C3D4-...",
  "title": "zsh",
  "pwd": "/Users/ted/montty",
  "focused": true,
  "size": {"rows": 24, "cols": 80, "width_px": 1200, "height_px": 800}
}
```

### POST /action

Trigger a Ghostty keybind action.

```bash
curl -s -X POST localhost:9876/action -d 'copy_to_clipboard'
```

### POST /jump

Enter jump mode or jump directly to a surface by leaf ID.

```bash
# Enter jump mode (assigns labels, installs key monitor)
curl -s -X POST localhost:9876/jump | jq .

# Jump directly to a specific surface
curl -s -X POST localhost:9876/jump -d '<leaf_id>'
```

### GET /jump-state

Get current jump mode state (labels, buffer, active status).

```bash
curl -s localhost:9876/jump-state | jq .
```

### GET /hook-log

The last 200 hook events montty received on its socket, oldest first. Each entry
carries the `timestamp`, the `event` name, the `surface` it named, whether it
`matched` a live surface, and the `new_state` it produced when it did.

```bash
curl -s localhost:9876/hook-log | jq .
```

### GET /claude-states

The current activity state of every surface that has one, whether a hook or
`montty surface status` set it. Each entry carries `tab_id`, `surface_id`,
`montty_surface_id`, and `state` (`working`, `waiting`, or `idle`). A `waiting`
surface also reports `waiting_since` and `waiting_seconds`, which is what the
idle sweep measures.

```bash
curl -s localhost:9876/claude-states | jq .
```

### GET /palette

The tab palette montty derived from the Ghostty config: the ANSI-16 colors read
through the C API (`ansi16`), the palette actually loaded (`loadedPalette`), and
any `configErrors`. Useful when tab colors do not match the theme.

```bash
curl -s localhost:9876/palette | jq .
```

### GET /icon

What macOS believes the app icon is, from four sources (the bundle keys,
`NSApp.applicationIconImage`, `NSImage(named:)`, and LaunchServices), with the
representations each one carries. Useful for diagnosing a stale icon cache.

```bash
curl -s localhost:9876/icon | jq .
```

## justfile recipes

| Recipe | Description |
|--------|-------------|
| `just inspect-surfaces` | List all surfaces |
| `just inspect-windows` | List open windows with their key state and tab count |
| `just inspect-type "text"` | Type text into terminal |
| `just inspect-key return` | Send a key event |
| `just inspect-screen` | Read terminal text |
| `just inspect-screenshot` | Save screenshot to `.llm/inspect/` |
| `just inspect-state` | Get terminal state |
| `just inspect-jump` | Enter jump mode |
| `just inspect-jump <leaf_id>` | Jump to a specific surface |
| `just inspect-jump-state` | Show jump mode state |
| `just inspect-action <action>` | Trigger a Ghostty keybind action |
| `just inspect-hook-log` | Show the last 200 hook events |
| `just inspect-claude-states` | Show per-surface activity state |
| `just inspect-palette` | Show the tab palette and config errors |
| `just inspect-session` | Show the session snapshot montty would write right now |
| `just inspect-icon` | Show app icon state |

`inspect-type`, `inspect-key`, `inspect-screen`, `inspect-screenshot`, `inspect-state`, and `inspect-action` accept an optional `surface=<uuid>` parameter to target a specific surface. The rest are app-wide.

## Example workflow

```bash
# Start the app
just run &

# Wait for it to initialize
sleep 2

# Type a command and execute it
just inspect-type "echo hello world"
just inspect-key return

# Read the output
just inspect-screen | jq -r .text

# Take a screenshot
just inspect-screenshot
```
