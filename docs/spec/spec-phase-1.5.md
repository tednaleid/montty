# Phase 1.5: Debug Server for Terminal Automation

## Goal

Add a debug-only HTTP server that enables programmatic terminal interaction: sending keystrokes, reading output, and capturing screenshots. This is the terminal equivalent of Playwright for browsers. Only compiled into Debug builds (`#if DEBUG`).

## Endpoints

All endpoints that interact with a surface accept an optional `?surface=<id>` query param. If omitted, the focused surface is used.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/surfaces` | List all surfaces with id, title, pwd, focused, size |
| `POST` | `/type` | Send text as if typed. Body = raw text |
| `POST` | `/key` | Send key event. Body = JSON `{"key": "return"}` or `{"key": "c", "ctrl": true}` |
| `GET` | `/screen` | Read visible terminal text. Returns JSON |
| `GET` | `/screenshot` | Capture terminal view as PNG |
| `GET` | `/state` | Terminal state: title, pwd, size |
| `POST` | `/action` | Trigger Ghostty keybind action. Body = action string |

## Technical approach

- Network.framework TCP listener on localhost:9876
- Static enum, no instance state
- `#if DEBUG` at file level
- Surface discovery via NSWindow view hierarchy walk
- GhosttyKit C APIs for terminal interaction

## File changes

| File | Change |
|------|--------|
| `Sources/App/DebugServer.swift` | New: HTTP server, routing, handlers |
| `Sources/App/AppDelegate.swift` | Modify: start/stop in #if DEBUG |
| `Tests/DebugServerTests.swift` | New: parsing and formatting tests |
| `docs/debug-server.md` | New: usage documentation |
| `CLAUDE.md` | Modify: reference debug-server.md |
| `justfile` | Modify: add inspect-* recipes |
| `docs/spec/progress.md` | Modify: add Phase 1.5 checklist |

## Verification

- `just run` prints "[DebugServer] Listening on localhost:9876"
- `just inspect-surfaces` lists the active surface
- `just inspect-type "echo hi"` + `just inspect-key return` executes a command
- `just inspect-screen` shows terminal text
- `just inspect-screenshot` saves viewable PNG
- `just test` passes
