# montty CLI

`montty` restyles the terminal surface and tab it runs in. It ships inside the
app bundle, and montty appends that bundle directory to `PATH` for every shell
it spawns, so `montty` resolves in any montty pane with no install step. Panes
also get `MONTTY_BIN` pointing at it by absolute path, for scripts that rewrite
`PATH`.

It only works from inside a montty pane. Run it anywhere else and it exits 2,
because there is no surface for it to act on.

## Commands

```
montty surface color <spec>          montty surface color --reset
montty tab     color <spec>          montty tab     color --reset
montty repo    color <spec>          montty repo    color --reset
montty tab     name  <text>          montty tab     name  --reset
montty surface status <working|waiting|idle|clear>
montty info
montty --version
```

`<spec>` is 1 to 3 comma-separated stops rendered as a left-to-right gradient.
A stop is a palette name resolved through your Ghostty theme (`green`,
`brightMagenta`, `neutralBright`; case and `-`/`_` are ignored) or a six-digit
hex value with or without a leading `#`.

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
| 3 | montty is not running |
| 64 | usage error: bad color spec, unknown scope or property |

## Activity status

`montty surface status` drives the same pane indicator Claude Code's hooks use,
so any long-running command can report progress:

```bash
just check && montty surface status idle || montty surface status waiting
```
