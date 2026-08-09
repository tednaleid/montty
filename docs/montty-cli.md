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

## Commands

```
montty surface color <spec>          montty surface color --reset
montty tab     color <spec>          montty tab     color --reset
montty repo    color <spec>          montty repo    color --reset
montty tab     name  <text>          montty tab     name  --reset
montty surface status <working|waiting|idle|clear>
montty info
montty --version
montty --help
```

`<spec>` is 1 to 3 comma-separated stops rendered as a left-to-right gradient.
A stop is a palette name resolved through your Ghostty theme (`green`,
`brightMagenta`, `neutralBright`; case and `-`/`_` are ignored) or a six-digit
hex value with or without a leading `#`.

A request, tab name included, is capped at 1 MiB. A larger one is rejected with
an error rather than truncated.

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
| 1 | montty rejected the request (unknown surface, not in a repo) |
| 2 | not running inside a montty pane |
| 3 | montty is not reachable: not running, or busy and refusing connections |
| 64 | usage error: unknown verb or property, bad color spec, extra arguments |

## Activity status

`montty surface status` drives the same pane indicator Claude Code's hooks use,
so any long-running foreground process can report progress:

```bash
montty surface status working
just check
montty surface status idle
```

`waiting` persists only as long as the caller keeps the foreground -- it clears
the moment control returns to a shell prompt, because an ordinary interactive
prompt re-emits the terminal title, and any title change clears `waiting`.
That makes it useful from inside a long-lived foreground process, such as a
script blocked on user input, but not from a one-off
`cmd && montty surface status waiting` typed at a normal prompt. `working` and
`idle` are not cleared by a title change, so they persist however you set
them.
