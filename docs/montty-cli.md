# montty CLI

`montty` restyles the terminal surface and tab it runs in. It ships inside the
app bundle, and montty appends that bundle directory to `PATH` for every shell
it spawns, so `montty` resolves in any montty pane with no install step. Panes
also get `MONTTY_BIN` pointing at it by absolute path, for scripts that rewrite
`PATH`.

Most commands only work from inside a montty pane -- run one anywhere else and
it exits 2, because there is no surface for it to act on. The exceptions:
`montty --version` and `montty --help` print and exit 0 from anywhere,
`montty install-hooks` and `montty uninstall-hooks` only edit a file and run
from anywhere, and `montty hook <event>` also exits 0 outside a pane, since a
hook firing there is normal, not an error.

Anything montty cannot parse exits 64 and prints what was wrong, the usage
line of the part of the command it recognised, and where to find its help: a
bad setting, value, or color; a mistyped scope such as
`montty tabb color green`; and an argument past the end of a command, so
`montty tab name MR 123` is an error rather than a tab named `MR`. A value
that starts with `-` goes after `--`, as in `montty tab name -- -draft`. The
GUI launches only with no arguments at
all, or with a flag montty does not define, which is how macOS starts the app
(`-psn_0_12345`, `-NSDocumentRevisionsDebugMode`).

A GUI launch while montty is already running raises every window already open
and exits, rather than starting a second app. So a mistyped flag such as
`montty --verison` costs a window raise, not a second montty taking over the
first one's socket and session file. See [One instance](../README.md#one-instance).

## Commands

Every setting is spelled `montty <scope> <setting>` followed by one of three
things:

| form | does |
|---|---|
| `montty tab color green` | sets the value at that scope |
| `montty tab color --reset` | removes the value at that scope; at the `app` scope, returns the setting to its default |
| `montty tab color` | prints what that scope resolves to |

The scopes are `surface`, `tab`, `repo`, and `app`. The first three are the
surface the command runs in, its tab, and its repo. `app` is the whole app,
across all windows.

| setting | scopes | value |
|---|---|---|
| `color` | `surface`, `tab`, `repo` | `<spec>`, 1 to 3 color stops |
| `name` | `tab` | text |
| `status` | `surface` | `working`, `waiting`, `idle`, or `clear` |
| `resume-command` | `surface` | a shell command |
| `surface-tint-strength` | `app` | 0 to 0.5, default 0.12 |
| `tab-tint-strength` | `app` | 0 to 0.3, default 0.12 |
| `minimap` | `tab`, `app` | `always`, `never`, or conditions; default `always` |
| `minimap-height` | `app` | 40 to 200 points, default 90 |

The rest are verbs:

```
montty info
montty hook <event>
montty install-hooks claude          montty uninstall-hooks claude
montty --version                     montty -v
```

`--help` or `-h` after any part of a command prints help for that part:
`montty --help` lists the scopes and verbs, `montty tab --help` lists the
settings a tab has, and `montty tab color --help` describes the color spec and
shows the palette.

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

Every command targets the surface it runs in, which resolves no matter which
window holds it. There is no window scope.

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
| 1 | montty rejected the request (unknown surface, not in a repo, tab name over 256 characters, invalid resume command, a settings file that is not a JSON object) |
| 2 | not running inside a montty pane |
| 3 | montty is not reachable: not running, or busy and refusing connections |
| 64 | usage error: unknown scope, setting, or verb, a setting at a scope that does not accept it, a bad value, extra arguments, request over 1 MiB |

## Claude Code hooks

montty learns what Claude Code is doing through Claude's hooks: they drive the
activity status and keep the resume command current. Add them to Claude Code's
user settings once:

```bash
montty install-hooks claude
montty uninstall-hooks claude
```

`install-hooks` adds a `SessionStart`, `UserPromptSubmit`, `PreToolUse`,
`Notification`, `Stop`, and `SessionEnd` entry to `~/.claude/settings.json`
(`$CLAUDE_CONFIG_DIR/settings.json` when that is set), each running:

```sh
[ -z "$MONTTY_BIN" ] || "$MONTTY_BIN" hook <event> --hooks-version <n>
```

Every montty pane sets `MONTTY_BIN` to the running app's binary, so a session
reports to the montty that owns its pane, and the entry does nothing in any
other terminal. What montty does with each event lives in that binary and
updates with montty.

`--hooks-version` is the version of the entries themselves, separate from
montty's release version. It changes only when montty needs different entries,
such as another event. When a Claude session starts with entries older than the
running montty's, Claude shows a message asking you to run
`montty install-hooks claude` again. Entries newer than the running montty say
nothing.

`install-hooks` brings montty's entries to the current set: it adds missing
ones, replaces outdated ones, and leaves current ones where they are, so
running it again is how you update. Both commands change only montty's entries
and leave every other setting and hook in place. The file keeps its key order
and Claude Code's own 2-space formatting, so the change is only the lines
montty adds or removes, and uninstalling gives back the file as it was. Before
changing the file, they save the previous one next to it as
`settings.json.montty-backup`. A symlinked settings file is written through,
so it stays a link. A file that is not a JSON object is left alone, and the
command exits 1. Claude Code reads hooks when a session starts, so sessions
already running pick them up after a restart.

Only interactive sessions report. `claude -p` and SDK sessions set
`CLAUDE_CODE_ENTRYPOINT` to something other than `cli`, and `montty hook`
ignores them, so a script or an agent's tool call running `claude -p` in a pane
cannot replace that pane's status or resume command.

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

## Minimap

A tab row shows its minimap according to a minimap visibility, `<when>`:

| value | the row shows its minimap |
|---|---|
| `always` | always (the default) |
| `never` | never |
| `split` | while the tab has more than one surface |
| `status` | while any surface in the tab has an activity status, `idle` included |
| `split,status` | while either holds |

`montty app minimap` sets it for every tab in every window, and `--reset`
returns it to `always`. `montty tab minimap` overrides it for the tab the
command runs in, and `--reset` removes the override so the tab follows the app
value again. The same choices are in View > Minimaps and in the tab's
right-click menu.

```bash
montty app minimap split,status
montty tab minimap never
montty tab minimap
montty info | jq .settings.minimap
```

`montty info` reports each of `minimap`, `minimap_height`,
`surface_tint_strength`, and `tab_tint_strength` under `settings`, with the
value at each scope that has one and `effective`, what the calling surface
resolves to:

```json
"minimap": {"tab": "never", "app": "split,status", "effective": "never"}
```

A row with a hidden minimap shows no activity status and has no rectangle to
click for a specific surface. Clicking the row selects the tab and focuses the
surface that last had focus there. In jump mode, a tab that is not the active
one and has a hidden minimap gets a single label, drawn at the right edge of
its row, that jumps to that same surface.

`montty app minimap-height` sets how tall a shown minimap is, in points, for
every tab: 40 to 200, default 90. The activity indicator and jump labels stay the
same size at every height.

## Tint strength

A terminal surface is tinted with its color. `montty app surface-tint-strength`
sets how strong that tint is, for every surface: 0 to 0.5, default 0.12. View >
Toggle Surface Tint switches it off and on without changing the strength.

Each tab row in the sidebar is washed with the color of its tab's focused
surface. `montty app tab-tint-strength` sets how strong that wash is, for
every tab: 0 to 0.3, default 0.12, and 0 turns it off. The value is the strength of
a row that is not active and shows its minimap. The active row is a little
stronger, and a row with its minimap hidden is stronger again, because the row
is then the only place the tab's color shows.

## Resume command

A surface's resume command is typed at its prompt, without pressing Enter,
when a relaunch restores the session. You see it, can edit it, and run it with
one keystroke.

Claude Code sessions keep it current on their own: every Claude hook event sets
it to `claude --resume <session id>`, so a `/branch`, `/clear`, or `/resume`
moves it to the session you are in. Ending Claude yourself (`/exit`, Ctrl-D)
clears it. Claude ending because montty quit, the machine shut down, or its
surface closed keeps it.

Any other program can register one:

```bash
montty surface resume-command "nvim -S session.vim"
montty surface resume-command --reset
montty info | jq -r .resume_command
```

The command stays until something replaces or clears it, so a second relaunch
before you act on it offers it again. It takes one quoted value, at most 4096
characters, with no control characters: a newline would run the command
instead of waiting at the prompt, so montty rejects one with exit 1.
