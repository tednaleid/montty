# montty multi-window design

## Goal

Cmd-N opens a new montty window. Each window owns its own tabs, splits, and
sidebar. Windows persist across quit, and a window closed by hand stays closed.

## Non-goals

Tabs do not move between windows. There is no drag-and-drop reparenting and no
"move tab to new window" command. A tab is created in a window and closes with
it. Adding this later does not require redesigning what is described here.

Windows are not a color or naming scope. There is no `montty window` verb and no
fourth precedence level. Pane color precedence stays surface, tab, repo, git
signature, gray.

## Ownership

`AppDelegate` currently is the window: it holds `var window: NSWindow!`, a single
`TabStore`, and every tab operation. That splits in two.

`WindowController` owns one `NSWindow`, one `TabStore`, that window's sidebar
width, and the per-window operations: creating, closing, and selecting tabs,
focus handling, and splits. It is its own window's `NSWindowDelegate`.

`AppDelegate` keeps what is genuinely app-wide: the Ghostty app handle, the
session store, repo color overrides, the surface tint toggle, the ANSI palette,
the tick timer, the stale status sweep, `HookServer`, and `DebugServer`. It gains
`var windows: [WindowController]` and one new job, routing:

```swift
func controller(forSurface id: UUID) -> (WindowController, Tab)?
```

That lookup is the seam. `HookServer`, `ControlService`, and `DebugServer` reach
into a single `tabStore` today, meaning "the one and only window". Each becomes a
routing call, which leaves no single-window assumption behind.

The surface-to-window index is a plain type with no AppKit dependency, so routing
is unit-testable in the existing test target.

`AppDelegate` is an `ObservableObject` consumed as an `EnvironmentObject` by
`TabRow`, and `TabSidebar` and `MainWindow` read `tabStore` directly. Per-window
state moving out means those views take the `WindowController` as an environment
object. This is the largest uncertain part of the work.

## Window lifecycle

A new window opens with one tab whose working directory is the focused surface's
directory, the rule `createTab` already applies. Placement cascades from the
frontmost window.

Closing a window closes its tabs and tears down their Ghostty surfaces, then
drops the controller from `windows`. There is no confirmation prompt, matching
how closing a tab behaves.

Closing the last window, or the last tab in the last window, quits montty. This
is what closing the last tab does today.

A window's title is its active tab's display name, so windows are distinguishable
in the Window menu and in Mission Control.

`MenuBuilder` targets the single window today and must target the key window.
Every menu command needs auditing against that change.

## Persistence

Session schema version 4 holds app-wide fields and an array of windows.
`TabSnapshot` does not change.

```swift
struct SessionSnapshot {
    var version: Int                             // 4
    var surfaceTintEnabled: Bool
    var repoColorOverrides: [String: PaneTint]
    var windows: [WindowSnapshot]
    var keyWindowID: UUID?
}

struct WindowSnapshot {
    var windowID: UUID
    var x, y, width, height: Double
    var sidebarWidth: Double
    var activeTabID: UUID?
    var tabs: [TabSnapshot]
}
```

`surfaceTintEnabled` and `repoColorOverrides` stay app-wide. Repo colors are
keyed by repo identity and shared by every window that opens that repo.
`sidebarWidth` moves into the window, since each window has its own sidebar.

### Migration

`SessionSnapshot.init(from:)` handles both shapes. When `windows` is present the
file is v4. Otherwise it builds one window from the v3 flat fields `windowX`,
`windowY`, `windowWidth`, `windowHeight`, `sidebarWidth`, `activeTabID`, and
`tabs`. A v3 file upgrades on the first save.

Every field decodes with `decodeIfPresent`, `windows` included, defaulting to an
empty array. A version 5 file read by a version 4 build then degrades to a cold
launch rather than throwing and being quarantined as corrupt.

A version 4 file has no top-level `tabs` key. A version 3 build requires that key
and decodes before it checks the version, so it treats a v4 file as corrupt and
moves it to `session.corrupt-<epoch>.json`. Nothing is destroyed and the file can
be recovered by hand. The cost of a rollback is recreating tabs.

### What a save records

The snapshot is live state at the moment it is written, by the eight second
autosave and again at quit. A closed window is absent from the next write. Two
windows open at quit restore two windows. Close one and quit, and only the
remaining one restores.

No tombstones and no history are needed to get that behavior, which is why this
is a snapshot rather than an event log. An event log would need an explicit
window-closed event and replay logic to reach the same answer that a snapshot
reaches by construction.

### Restore

Each window's frame is clamped to a visible screen, so a window saved on a
display that is no longer attached comes back on screen. `keyWindowID` restores
focus to the window that had it.

## Control CLI and hooks

`MONTTY_SURFACE_ID` identifies a surface, and every `montty` command is
self-targeting, so no command grammar changes. The routing lookup replaces the
single-store lookup inside `ControlService` and `HookServer`.

The instance guard, the hook socket, and the lock file are unchanged. montty
remains one process, so there is still one socket, one lock, and one owner.

## Debug server and inspect recipes

`/surfaces` gains a window identifier on each surface, along with the window's
frame and whether it is key. Without it a flat surface list cannot be attributed
to a window.

`inspect-screenshot` activates the application by name, which raises the app
rather than the window holding the requested surface. Against two windows, a
surface in the background window is captured occluded. The screenshot path must
raise the window that owns the target surface.

Jump mode assigns labels to leaves and installs a key monitor. Labels cover the
key window's leaves only. Jumping is a way to move focus within the window in
front of you, and labeling every leaf in every window makes the label set larger
and the labels longer for no gain.

`/type`, `/key`, `/screen`, and `/state` already take a surface parameter and
work unchanged once routing resolves surfaces across windows. `/hook-log`,
`/claude-states`, `/palette`, and `/icon` are app-wide and unaffected.

## Developing montty inside montty

`just run` and `just run-bg` set `MONTTY_SESSION_DIR` and `MONTTY_SOCKET` under
the build directory. The instance guard derives its lock path from the socket
path, so a development build takes a different lock, binds a different socket,
and writes a different session file from the montty hosting the shell. The two
coexist, and this design does not change that.

The debug server binds port 9876 with no environment override, so only one debug
build can serve it at a time. That constraint exists today and is unchanged here.

## Testing

Tests stay pure model tests with no AppKit, in the existing target.

- Snapshot round trip across several windows, each with tabs, splits, and color
  overrides.
- Migration from a v3 file taken from a real Application Support directory rather
  than a hand-written fixture. A synthetic fixture is what allowed the v2 decode
  regression to ship.
- A v4 file with no `windows` key decodes to zero windows rather than throwing.
- Closing a window removes it from the next snapshot, and closing the last one
  produces a snapshot that restore treats as a cold launch.
- Frame clamping returns an on-screen frame for a window saved off-screen.
- Routing resolves a surface to its owning window and tab, and returns nothing
  for an unknown surface.

## Risks

The SwiftUI environment-object rework in the view layer is the largest uncertain
piece of the work.

Closing a window must tear down its Ghostty surfaces. Surfaces that outlive their
window leak, and Ghostty's C API must be called on the main actor.
