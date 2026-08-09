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
    "tab_id": "C9D0E1F2-...",
    "tab_name": "montty",
    "tab_position": 0,
    "tab_color": "blue",
    "active": true,
    "focused_in_tab": true,
    "focused": true,
    "split_count": 1,
    "title": "zsh",
    "pwd": "/Users/ted/montty",
    "size": {"rows": 24, "cols": 80, "width_px": 1200, "height_px": 800},
    "color": {
      "effective": ["neutralBright", "#1a7f37"],
      "source": "surface",
      "surface_override": ["#1a7f37"],
      "tab_override": null,
      "repo_override": {"identity": "/Users/ted/montty", "stops": ["cyan"]}
    }
  }
]
```

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

### GET /screenshot

Capture the terminal view as a PNG image.

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

## justfile recipes

| Recipe | Description |
|--------|-------------|
| `just inspect-surfaces` | List all surfaces |
| `just inspect-type "text"` | Type text into terminal |
| `just inspect-key return` | Send a key event |
| `just inspect-screen` | Read terminal text |
| `just inspect-screenshot` | Save screenshot to `.llm/inspect/` |
| `just inspect-state` | Get terminal state |
| `just inspect-jump` | Enter jump mode |
| `just inspect-jump <leaf_id>` | Jump to a specific surface |
| `just inspect-jump-state` | Show jump mode state |

All inspect recipes except `inspect-jump` and `inspect-jump-state` accept an optional `surface=<uuid>` parameter to target a specific surface.

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
