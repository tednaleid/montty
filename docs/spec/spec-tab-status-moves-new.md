# Tab Status, Moving Tabs Between Windows, and `montty tab new`

## Goal

Make a sidebar full of tabs with hidden minimaps say which tabs need the user,
let a tab move to another window or into a window of its own, and let a
program in a surface open tabs.

Terms used here (Tab Status, Tear Off, Activity Status, Minimap Visibility,
Surface) are defined in [GLOSSARY.md](../../GLOSSARY.md).

## Tab status

A tab's status is the most urgent activity status among its surfaces: waiting,
then idle, then working. It does not follow focus. A tab whose surfaces have
no activity status has no tab status.

The tab's color, tint and name come from its focused surface because they say
which tab this is. The status says whether anything in the tab needs the user,
so it covers every surface.

### On the row

A row whose minimap is hidden shows the tab status as one indicator at the
right end of the name line, so the indicators of consecutive rows line up in a
column. A row whose minimap is showing draws no row indicator, since each
minimap rectangle already carries its surface's status.

The indicator uses the glyphs the minimap uses (the cycling star for working,
`*?` for waiting, `*` for idle) at a size that fits the name line.

Clicking the row selects the tab and focuses its focused surface, as before.
It does not go to the surface the status came from.

This replaces the line in
[spec-minimap-visibility.md](spec-minimap-visibility.md) that says a hidden
minimap row shows no activity status.

### Waiting lasts until a key press

A waiting status ends when:

- the program reports a different status, or
- the user presses a key in that surface, which makes it idle. If the program
  carries on, its next report says working.

Nothing else ends it. The 60 second timeout and the rule that a title change
clears waiting are removed, along with the tagging that exempted a waiting set
by `montty surface status` from them.

A report that never arrives leaves waiting on the surface until the user
presses a key there.

The key press is reported by one `// MONTTY:` notification in
`SurfaceView_AppKit.swift`'s `keyDown`. The debug server's type and key
endpoints post the same notification.

## Moving a tab between windows

Dragging a tab onto a sidebar moves it to the gap the cursor is nearest: above
a row in the row's upper half, below it in the lower half, and at the end of
the list below the last row. The sidebar may belong to the tab's own window (a
reorder) or another one.

- The tab moves whole: surfaces, surface names, colors, overrides, minimap
  setting. No surface is created or destroyed, so its shells keep running.
- It becomes the active tab of the window it lands in, and that window comes
  to the front.
- A window left with no tabs closes.
- An insertion line shows the gap. No line is drawn where a drop would leave
  the tab where it is. Rows part slightly around the line, and tabs slide to
  their places on drop.
- The drag carries the tab id under a type declared for montty
  (`com.montty.app.tab`), so no other app accepts it.

`CLAUDE.md` and the README stop saying tabs never move between windows.

## Tear off

Releasing a tab drag at a point inside no montty window opens a new window
holding that tab.

- The new window is the size of the one the tab left, placed with its title
  bar under the cursor, and kept on the display the cursor is on.
- A window's only tab does not tear off.
- Minimized and closing windows do not count as being under the cursor.

"Move Tab to New Window" in the tab's context menu does the same without a
drag, placing the new window where Cmd-N would. It is disabled for a window's
only tab.

### The drag source

The drag is an AppKit dragging session started from an `NSView` behind each
row. The view watches mouse events with a local monitor and never takes one,
so the row's SwiftUI gestures (select, rename, context menu, minimap and jump
badge clicks) are unchanged. A press while a name is being edited does not
start a drag. AppKit reports where the drag was released, and the tear-off
decision is made from that point and the window frames. Whether a drop target
accepted the drag is not used.

A spike of this passed every gesture check by hand. SwiftUI's own drag was
ruled out because it does not report a release over nothing, which the fork
worked around by polling the mouse button.

A released drag that tears off does not animate back to its row.

## `montty tab new`

```
montty tab new [--dir <path>] [--name <text>] [--focus] [-- <command> [<argument>...]]
```

Opens a tab in the window of the surface that ran the command.

- The tab is added at the end of that window's tabs.
- It opens in the background. `--focus` makes it the active tab.
- Its shell starts in `--dir`, or in the calling surface's directory.
  A relative path or `~` resolves against where the command was run. A path
  that is not an existing directory is a usage error (exit 64), reported
  before anything is sent.
- `--name` sets the tab name.
- Everything after `--` is a command the new shell runs, with its arguments.
- It prints nothing on success.
- A request from a surface montty no longer knows opens nothing.

`new` is a verb under a scope. The grammar in
[spec-cli-grammar.md](spec-cli-grammar.md) gains: a scope may have verbs as
well as settings.

### How the command reaches the new shell

Text typed into a terminal acts on control characters as they arrive, before
the shell reads any quoting, so an argument holding a newline cannot be typed
safely. The arguments are therefore never typed and never placed in the
environment.

The app keeps the command for the new surface. The new shell is typed one
fixed line, `"$MONTTY_BIN" launch`, and runs it. `montty launch` asks the app
for the command kept for its surface, receives it once, and replaces itself
with it. When the command exits, the shell prompt returns.

- `launch` is not listed in help.
- A second `montty launch` in the same surface, or one in a surface with no
  command kept, prints an error and exits 1.
- An argument may hold any text except a NUL byte. Arguments total at most
  100,000 characters.
- Shell history shows the `launch` line, not the command.

A tab opened with a command is an ordinary tab afterward. Restoring the
session does not run the command again.

## Structure

- `ActivityStatus.State.mostUrgent(of:)` and `TabInfo.activity` hold the
  ranking. `TabRow` draws from them.
- `TabStore.detach(id:)` and `insert(tab:at:)`; `close` is `detach` plus the
  closed-directory record.
- `WindowUseCases.moveTab`, `tabDragEnded`, `moveTabToNewWindow`, and
  `openTab` make every decision and return a `WindowOutcome`.
  `TabDropTarget` works out gaps and landing indexes. `Sources/App` supplies
  window frames, screens and the release point, and applies outcomes.
- `SurfacePlan.runsLaunch` says a new surface types the launch line.
  `WindowUseCases` keeps each command by montty surface id until
  `takeLaunch` hands it over.
- `ControlCommand.newTab` and `takeLaunch`, the second sent as a `launch`
  request on the control socket and answered with the command.
- Debug server: `POST /move-tab` and `POST /tear-off`, with
  `just inspect-move-tab` and `just inspect-tear-off`.

## Order of work

Four commits, each leaving the app shippable.

1. Tab status on hidden-minimap rows, and waiting until a key press.
2. Moving a tab between windows, with the drag source, the insertion line, and
   the `CLAUDE.md` and README changes.
3. Tear off and "Move Tab to New Window".
4. `montty tab new` and `montty launch`.

## Testing

Unit tests:

- Most urgent of each mix of states; no states gives none.
- `TabInfo.activity` is independent of which surface is focused.
- Waiting survives the passage of time and a title change; a key press makes
  it idle; a key press on a surface that is not waiting changes nothing.
- `detach` and `insert` keep positions contiguous and the active tab valid.
- `moveTab`: reorder, move to another window, the emptied window closes, an
  unknown tab or window changes nothing, overrides and surface names arrive
  with the tab.
- Gap and landing index for a tab from this window and from another.
- `tabDragEnded`: over a window, over nothing, only tab, clamping to the
  display under the cursor.
- `tab new` parsing: each flag, `--` with arguments that start with a dash,
  unknown flags, directory resolution.
- `openTab`: placement, focus, directory fallback, unknown caller.
- The kept command is handed over once.

Through the debug server:

- A hidden-minimap row shows waiting for a tab whose unfocused surface is
  waiting, in a screenshot.
- `inspect-move-tab` between two windows keeps a running shell's screen
  content.
- `inspect-tear-off` opens a window; on a window's only tab it does not.
- `montty tab new -- <command>` with an argument holding a newline, a quote
  and a `$` runs with that argument intact.

By hand: a real drag to another window, to the desktop, and cancelled with
Escape.
