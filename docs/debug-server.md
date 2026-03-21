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
    "title": "zsh",
    "pwd": "/Users/ted/montty",
    "focused": true,
    "size": {"rows": 24, "cols": 80, "width_px": 1200, "height_px": 800}
  }
]
```

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

## justfile recipes

| Recipe | Description |
|--------|-------------|
| `just inspect-surfaces` | List all surfaces |
| `just inspect-type "text"` | Type text into terminal |
| `just inspect-key return` | Send a key event |
| `just inspect-screen` | Read terminal text |
| `just inspect-screenshot` | Save screenshot to `.llm/inspect/` |
| `just inspect-state` | Get terminal state |

All inspect recipes accept an optional `surface=<uuid>` parameter to target a specific surface.

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
