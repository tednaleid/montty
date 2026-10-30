# Resume Command: pick up where a surface left off after a relaunch

## Goal

montty restores every surface's working directory on relaunch, but not the
program that was running in it. The costly case is Claude Code: resuming a
session needs its id (`claude --resume <id>`), and with several Claude sessions
in the same directory, `claude --continue` picks the wrong one. Today the only
way to keep those ids across a montty update or a reboot is to exit each session
by hand and copy its resume command somewhere.

Each surface gets an optional **Resume Command** (see `GLOSSARY.md`). Claude
Code's hooks keep it current automatically. On relaunch, montty types it at the
surface's prompt without pressing Enter, so getting back is one keystroke per
surface and nothing runs without being seen first.

## Behavior

### What sets it

- **Claude hooks.** Every hook event from a Claude session in a surface sets
  that surface's resume command to `claude --resume <session_id>`, using the
  `session_id` in the hook payload. Every event carries the current id, so a
  `/branch`, `/clear`, or in-session `/resume` moves the record to the new
  session by the next prompt or tool call.
- **The CLI.** `montty surface resume-command "<cmd>"` sets it by hand, for any
  program. `montty surface resume-command --reset` clears it.

The most recent writer wins. A Claude session started in a surface whose
resume command was set by hand replaces it.

### What clears it

- A Claude `SessionEnd` whose `reason` marks the person ending it:
  `prompt_input_exit` (`/exit`, Ctrl-D) or `logout`. A `clear` reason is
  followed by a `SessionStart` that sets the new id, so it is treated the
  same way.
- Any other `reason`, or none, keeps the record. Claude dying because its
  surface closed, montty quit, or the machine shut down must not lose the
  session, and a stale prefill costs far less than a lost session id.
- `montty surface resume-command --reset`.
- Closing the surface, tab, or window, which removes the surface and everything
  recorded for it. Reopening a recently closed window gives plain prompts.

### Restore

On a relaunch restore, each surface with a resume command gets it as Ghostty's
`initial_input`, with no trailing newline: the text sits at the prompt, editable,
until Enter. The record stays on the surface after restore, so a second
relaunch before acting on it offers it again. It goes away only by one of the
clearing paths above.

Only a relaunch restore prefills. A new tab, split, or window never does.

### Validation

A resume command is typed into a shell, so it must never press Enter or send
an escape sequence on its own:

- Any control character (U+0000 to U+001F, U+007F) rejects the request. The CLI
  exits 1.
- More than 4096 characters rejects the request. The CLI exits 1.
- The CLI takes exactly one value, like `tab name`. An unquoted multi-word
  command is a usage error (exit 64). montty stores and types the string exactly
  as it arrives and never re-quotes it.
- A hook `session_id` that is not made only of letters, digits, `-`, and `_` is
  ignored, so a malformed payload cannot build a command that does anything but
  resume.

### Visibility

`montty info` reports `resume_command` for the calling surface. The key is
omitted when none is set, so `jq -r .resume_command` prints `null`.

## Design

Decisions stay in `Sources/Model` and `Sources/UseCase`; `Sources/App` only
forwards and runs effects (see `docs/architecture.md`).

- **Hook payload.** `montty hook <event>` forwards `session_id` and `reason`
  from Claude's stdin payload alongside `cwd`. `ClaudeHookMessage` parses both
  as optional fields, so an older wrapper still works.
- **Tracking.** A pure `ResumeCommandTracker`, next to `HookDirectoryTracker`,
  applies a hook message to a surface's resume command: set from `session_id`,
  clear on a deliberate `SessionEnd`, otherwise leave it.
- **Control.** `ControlCommand.setResumeCommand(String?)`, with nil as reset.
  Wire form: `{"cmd":"set","prop":"resumeCommand","value":<string|null>}`.
  `ControlRequest.decode` enforces the validation rules, as it does for the tab
  name cap. `ControlInfo` gains `resumeCommand`.
- **Model.** `Tab.resumeCommands: [UUID: String]`, keyed by surface id like
  `surfaceColorOverrides`.
- **Persistence.** `TabSnapshot.leafResumeCommands: [UUID: String]`, keyed by
  leaf id, decoded with `decodeIfPresent` so older session files load. No
  snapshot version bump.
- **Restore.** `WindowUseCases.restore` puts each leaf's resume command on its
  `SurfacePlan`. `createSurfaces` passes it to Ghostty as `initialInput` and
  records it on the tab under the new surface id, the same way it records the
  restored working directory.

## Claude Code hook behavior

Observed against Claude Code 2.1.312 in a dev build:

- `/branch` fires `SessionEnd` with reason `resume` for the original session,
  then `SessionStart` with source `fork` and the branched session's id. The
  resume command moves to the branch immediately.
- `/exit` reports reason `prompt_input_exit`.
- Quitting montty with Claude running reports reason `other`, so the resume
  command is kept and saved.
- `claude --resume <id>`, run from the restored surface's directory, brings
  back the conversation.

Not yet observed: resuming a session that entered a worktree, where Claude's
cwd differs from the shell's.

## Known rough edge

Ghostty writes `initial_input` to the pty before the shell disables echo, so
the command also appears once above the shell's first output, as well as at
the prompt.
