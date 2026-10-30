# Install hooks: Claude Code reports to montty however it was launched

## Goal

montty's Claude Code activity status and resume command both come from
Claude's hook events. montty used to inject those hooks with a zsh `claude()`
function appended to Ghostty's shell integration, which passed `--settings` on
each launch. That function only exists in the interactive shell of a surface,
so any Claude started another way, such as a launcher script that `exec`s the
`claude` binary, `command claude`, or a `just` recipe, never reported: no
status indicator, and no resume command after a relaunch.

`montty install-hooks claude` puts the hooks in Claude Code's user settings
instead, where every Claude process reads them.

## Behavior

### Commands

- `montty install-hooks claude` adds one entry per event to the settings file.
- `montty uninstall-hooks claude` removes them.
- The agent name is required. Only `claude` is accepted; anything else is a
  usage error (exit 64). The name leaves room for other agents, each of which
  needs its own settings format, event mapping, and resume command.
- Both run from anywhere, since they only edit a file.

### The installed entries

`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `Notification`, `Stop`, and
`SessionEnd` each get a group with one command:

```sh
[ -z "$MONTTY_BIN" ] || "$MONTTY_BIN" hook <event>
```

- `MONTTY_BIN` is set in every surface to the running app's binary, so the
  command reports to the montty that owns the surface, a dev build included.
- Outside montty the guard exits 0, so Claude never reports a hook error.
- The text does not depend on the montty version, so a release never needs to
  rewrite the user's settings.
- montty's entries are recognized by containing `"$MONTTY_BIN" hook `.

### Editing the settings file

- The file is `$CLAUDE_CONFIG_DIR/settings.json`, or `~/.claude/settings.json`
  when that is unset or empty. A symlink is resolved and its target written.
- Install adds montty's group to each event that has no montty entry, after
  the groups already there. Running it twice changes nothing.
- Uninstall removes montty's commands, then any group, event, or `hooks` key
  left empty. Other commands in a shared group stay.
- When the content changes, the previous file is saved as
  `settings.json.montty-backup` and the new one is written atomically,
  pretty-printed with sorted keys. When nothing changes, the file is not
  touched.
- A file that is not a JSON object is left alone, and the command exits 1. A
  missing file is created by install and ignored by uninstall.

### Which sessions report

`montty hook` forwards an event only when `CLAUDE_CODE_ENTRYPOINT` is `cli` or
unset. Hooks from a user-level settings file fire for every Claude process,
including `claude -p` run by a script or by an agent's tool call inside the
surface. Those would otherwise replace the surface's resume command with a
throwaway session id, and their `SessionEnd` would clear the status of the
interactive session still running there.

## Design

- `Sources/Control/ClaudeHooks.swift` holds the pure parts: the event list,
  the command text, `installing(into:)`, `uninstalling(from:)`, and
  `reportsSession(entrypoint:)`.
- `ControlArgs` parses `install-hooks <agent>` and `uninstall-hooks <agent>`
  into `ParsedInvocation.installHooks` and `.uninstallHooks`.
- `ControlCLI` reads and writes the file and checks the entrypoint before
  forwarding a hook.
- The `claude()` wrapper is gone from `project.yml`. Running both would send
  every event twice.

## Claude Code behavior

Observed against Claude Code 2.1.312:

- An interactive session's hooks see `CLAUDE_CODE_ENTRYPOINT=cli`.
- `claude -p` hooks see `CLAUDE_CODE_ENTRYPOINT=sdk-cli`, even when started
  from a shell whose environment already has `cli`.
