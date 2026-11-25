# montty

A macOS terminal where one process owns several windows, each holding tabs that
split into terminal surfaces, and that restores all of it on relaunch.

## Language

**Surface**:
One terminal region inside a tab, running its own shell.
_Avoid_: Pane, leaf

**Resume Command**:
The shell command a surface offers to re-run when montty restores it, so the
program that was running there can pick up where it left off.
_Avoid_: Restart command, startup command

**Activity Status**:
What the program in a surface reports it is doing: working, waiting on the
user, or idle. A surface with no report has no activity status.
_Avoid_: Claude indicator, status effect

**Minimap**:
The scaled drawing of a tab's surface layout shown in that tab's sidebar row,
one rectangle per surface.
_Avoid_: Mini map, thumbnail, preview

**Minimap Visibility**:
The rule deciding whether a tab's row shows its minimap: always, never, or
only while at least one named condition holds. Set app-wide, and optionally
overridden per tab.

**Split Condition**:
The minimap visibility condition that holds while a tab has more than one
surface.

**Status Condition**:
The minimap visibility condition that holds while any surface in the tab has
an activity status, idle included.
