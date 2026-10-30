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
