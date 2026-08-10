# montty CLI

`montty` restyles the terminal surface and tab it runs in. It ships inside the
app bundle, and montty appends that bundle directory to `PATH` for every shell
it spawns, so `montty` resolves in any montty pane with no install step. Panes
also get `MONTTY_BIN` pointing at it by absolute path, for scripts that rewrite
`PATH`.

Most commands only work from inside a montty pane -- run one anywhere else and
it exits 2, because there is no surface for it to act on. Two exceptions:
`montty --version` and `montty --help` print and exit 0 from anywhere, and
`montty hook <event>` also exits 0 outside a pane, since a hook firing there
is normal, not an error.

Anything montty cannot parse exits 64 and prints the usage text: a bad
property, value, or color; a mistyped verb such as `montty tabb color green`;
and an argument past the end of a command, so `montty tab name MR 123` is an
error rather than a tab named `MR`. The GUI launches only with no arguments at
all, or with a flag montty does not define, which is how macOS starts the app
(`-psn_0_12345`, `-NSDocumentRevisionsDebugMode`).

A GUI launch while montty is already running raises the window that is already
open and exits, rather than starting a second app. So a mistyped flag such as
`montty --verison` costs a window raise, not a second montty taking over the
first one's socket and session file. See [One instance](../README.md#one-instance).

## Commands

```
montty surface color <spec>          montty surface color --reset
montty tab     color <spec>          montty tab     color --reset
montty repo    color <spec>          montty repo    color --reset
montty tab     name  <text>          montty tab     name  --reset
montty surface status <working|waiting|idle|clear>
montty info
montty hook <event>
montty --version
montty --help
```

`<spec>` is 1 to 3 comma-separated stops rendered as a left-to-right gradient.
A stop is a palette name resolved through your Ghostty theme (`green`,
`brightMagenta`, `neutralBright`; case and `-`/`_` are ignored) or a six-digit
hex value with or without a leading `#`.

A tab name is capped at 256 characters, and a whole request at 1 MiB. Either
limit rejects the request rather than truncating it, so a name that arrives is
always the name that was typed. An over-long name exits 1, an over-size request
exits 64.

## Scopes

Colors resolve surface first, then tab, then repo, then the automatic git
signature:

| scope | affects |
|---|---|
| `surface` | the one pane that ran the command |
| `tab` | every pane in the tab that has no surface override |
| `repo` | every tab whose focused pane sits in this repo or worktree |

Each scope has its own Reset in the tab's right-click menu, so anything set here
can be cleared from the GUI.

## Examples

```bash
montty tab name "MR !123 fix auth"
montty tab color neutralBright,green
montty surface color "#1a7f37"
montty info | jq -r .git.branch
```

## Exit codes

| exit | meaning |
|---|---|
| 0 | ok |
| 1 | montty rejected the request (unknown surface, not in a repo, tab name over 256 characters) |
| 2 | not running inside a montty pane |
| 3 | montty is not reachable: not running, or busy and refusing connections |
| 64 | usage error: unknown verb or property, bad color spec, extra arguments, request over 1 MiB |

## Activity status

`montty surface status` drives the same pane indicator Claude Code's hooks use,
so any long-running foreground process can report progress:

```bash
montty surface status working
just check
montty surface status idle
```

`waiting` marks the pane as needing you, and it stays marked after control
returns to the shell prompt:

```bash
just deploy && montty surface status waiting
```

A `waiting` set here survives the terminal title changing, so a shell redrawing
its prompt does not wipe it. Claude Code's `waiting` behaves differently on
purpose: its TUI does not redraw the title while it is blocked, so a title
change there means the hook that should have cleared the state was lost, and
montty clears it.

Every `waiting`, however it was set, returns to `idle` after 60 seconds so a
pane cannot stay marked forever. `working` and `idle` persist until something
changes them.
