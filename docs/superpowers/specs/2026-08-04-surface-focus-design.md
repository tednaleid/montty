# Surface focus: centralized policy, tab-switch blur, cold-launch focus

## Problem

Two user-visible defects share one root cause.

**Cold launch does not give the terminal keyboard focus.** Launching montty from
a Mac launcher brings up the window, but typing does nothing until the user
clicks the window. Cmd-Tab back into an already-running montty and clicking the
Dock icon both work correctly.

**Switching tabs does not emit DEC mode 1004 focus reports.** With focus event
reporting enabled, moving between splits inside a tab correctly emits `ESC[O`
(blur) and `ESC[I` (focus). Switching between tabs emits nothing: the outgoing
surface never sees focus-out and the incoming surface never sees focus-in.
Consumers that depend on this include Claude Code session recaps, tmux
focus-events, neovim `FocusGained`/`FocusLost`, and fzf.

## Root cause

Upstream Ghostty centralizes focus in
`BaseTerminalController.syncFocusToSurfaceTree()`
(`ghostty/macos/Sources/Features/Terminal/BaseTerminalController.swift:299`).
It recomputes focus for every surface in the tree whenever a surface **or the
window** changes focus, and gates each surface on `window.isKeyWindow`.

Montty's analogue, `AppDelegate.updateSurfaceFocus(for:)`
(`Sources/App/AppDelegate.swift:274`), only ever touches one tab and ignores
window state. Four defects follow:

1. **Tab switch emits nothing.** `Sources/App/MainWindow.swift:61-68` handles
   `onChange(of: tabStore.activeTabID)` by calling `Ghostty.moveFocus(to:)` on
   the incoming surface only. Nothing blurs the outgoing tab, so its surface
   keeps `focused == true`. The incoming surface is also still `focused == true`
   from before, so it hits the early return in
   `SurfaceView_AppKit.swift:428` (`guard self.focused != focused else { return }`)
   and writes nothing either. That single guard explains both halves of the
   symptom.

2. **Montty assigns no `NSWindowDelegate`.** `window.delegate` is never set, so
   there is no `windowDidBecomeKey` or `windowDidResignKey`. The app-level path
   does not compensate: `ghostty_app_set_focus` calls `App.focusEvent`
   (`ghostty/src/App.zig:310`), which only sets a flag. The sole route to the
   escape-sequence write is `Surface.focusCallback`
   (`ghostty/src/Surface.zig:3259`) into `Termio.focusGained`
   (`ghostty/src/termio/Termio.zig:660`). Switching away from montty to another
   application therefore emits no blur today.

3. **Session restore focuses every tab.** `restoreSession`
   (`Sources/App/AppDelegate.swift:542`) loops `updateSurfaceFocus(for: tab)`
   across all tabs, so after a restore each tab has a surface libghostty
   believes is focused. It also never sets an AppKit first responder.

4. **New surfaces start focused.** `SurfaceView.focused` defaults to `true`
   (`SurfaceView_AppKit.swift:206`), so a surface created in a background tab is
   focused from libghostty's perspective before anything blurs it.

Cold launch adds a fifth: `applicationDidFinishLaunching` calls
`window.makeKeyAndOrderFront(nil)` but never activates the application.

## Scope decisions

Leaving montty entirely (Cmd-Tab to another app, hiding, minimizing) blurs the
focused surface and emits `ESC[O`, matching upstream Ghostty. Alt-tabbing to a
browser is the most common "walked away" case, so this is in scope even though
the original report only covered tab switching. The visible consequence is a
hollow cursor while montty is inactive, which is standard terminal behavior.

Each tab's `focusedLeafID` is pure model state and is not modified by any of
this work. The minimap continues to show which pane is active in each tab, and
re-activating a tab restores focus to that pane.

Transient in-app UI (surface jump mode) does not blur the surface. It is
short-lived and blurring would generate spurious recaps.

## Design

### 1. Pure focus policy

New file `Sources/Model/SurfaceFocus.swift`. One rule, one place:

> A surface is focused if and only if the window is key, the surface is in the
> active tab, and it is that tab's `focusedLeafID`.

```swift
enum SurfaceFocus {
    /// Focus state for every surface across every tab.
    static func plan(
        tabs: [Tab],
        activeTabID: UUID?,
        windowIsKey: Bool
    ) -> [UUID: Bool]  // surfaceID -> focused
}
```

No AppKit and no `Ghostty` import, so it is unit-testable in the existing fast
suite.

### 2. Applier

New file `Sources/App/AppDelegate+Focus.swift`, following the existing
`AppDelegate+GhosttyActions.swift` pattern so `AppDelegate.swift` does not grow.
`updateSurfaceFocus(for:)` is deleted. Its replacement is the only code in
montty permitted to call `focusDidChange`:

```swift
func syncSurfaceFocus() {
    let plan = SurfaceFocus.plan(
        tabs: tabStore.tabs,
        activeTabID: tabStore.activeTabID,
        windowIsKey: window?.isKeyWindow ?? false)
    for (id, on) in plan where !on { surfaces[id]?.focusDidChange(false) }
    for (id, on) in plan where  on { surfaces[id]?.focusDidChange(true) }
}
```

Two passes, blur before focus. A `[UUID: Bool]` has undefined iteration order,
and the outgoing surface must receive `ESC[O` before the incoming surface
receives `ESC[I`. The two passes enforce that ordering.

Call sites, each replacing a partial sync or an absent one:

| Site | Change |
| --- | --- |
| `MainWindow.onChange(of: tabStore.activeTabID)` | sync, then `Ghostty.moveFocus(to:)` |
| `AppDelegate.setFocusedLeaf(_:in:)` | `updateSurfaceFocus` becomes `syncSurfaceFocus` |
| `AppDelegate+GhosttyActions` `ghosttySurfaceFocused` observer | same substitution |
| `AppDelegate.createTab` / `splitSurface` / `closeTab` | sync after mutating the tree |
| `AppDelegate.restoreSession` | replace the per-tab loop with one sync |
| `windowDidBecomeKey` / `windowDidResignKey` | new, see below |

Because the sync runs after every surface creation, a surface born in a
background tab is blurred immediately, fixing defect 4. The C surface is created
synchronously in `SurfaceView.init` (`SurfaceView_AppKit.swift:380`), so
`focusDidChange` does not hit its `guard let surface` early return.

The `ghosttySurfaceFocused` observer already guards on
`tab.focusedLeafID != leaf.id` (`AppDelegate+GhosttyActions.swift:98`), and
`focusDidChange` guards on an unchanged flag, so routing the observer through
`syncSurfaceFocus` does not create a feedback loop.

### 3. Window delegate

`AppDelegate` conforms to `NSWindowDelegate` and sets `window.delegate = self`.

- `windowDidResignKey` calls `syncSurfaceFocus()`. This is what makes leaving
  montty emit `ESC[O`.
- `windowDidBecomeKey` calls `Ghostty.moveFocus(to:)` on the active tab's
  focused surface when `window.firstResponder == window`, then syncs on the next
  runloop. This mirrors upstream
  (`BaseTerminalController.swift:1231`), where the deferral exists because
  becoming key races responder updates during window activation.

### 4. Cold launch

In `applicationDidFinishLaunching`:

- Call `NSApp.activate()` after `makeKeyAndOrderFront(nil)`. Nothing activates
  the app today. Use the unqualified form, not the deprecated
  `activate(ignoringOtherApps:)`; the deployment target is macOS 26.
- In the post-layout restore block, replace the per-tab
  `updateSurfaceFocus(for:)` loop with a single `syncSurfaceFocus()` plus an
  explicit `Ghostty.moveFocus(to:)` on the active tab's focused surface.
- Apply the same treatment to the fresh-tab path taken when no snapshot exists.

`windowDidBecomeKey`'s first-responder recovery from section 3 is the backstop if
activation still races view layout.

## Testing

Red/green, policy tests first.

**Unit tests** (`Tests/`, Swift Testing, no AppKit) on `SurfaceFocus.plan`:

- Single tab, single surface, key window: that surface is focused.
- Window not key: no surface is focused, in any tab.
- Two tabs: only the active tab's `focusedLeafID` surface is focused; the
  background tab's `focusedLeafID` surface is not.
- Background tab retains its `focusedLeafID` after planning, so the minimap and
  re-activation are unaffected.
- Tab with `focusedLeafID == nil`: no surface in that tab is focused.
- A leaf in the active tab that is not `focusedLeafID` is not focused.
- Across any input, at most one surface is focused.

**Debug server:** `/surfaces` currently reports the model-level
`focused_in_tab` (`DebugServerHandlers.swift:118`) but not the libghostty
`focused` flag, which appears only on `/state`. Add `focused` to the `/surfaces`
listing so a single `just inspect-surfaces` call shows the whole picture and can
assert exactly one focused surface after a tab switch.

**Manual acceptance**, per the original report:

1. In a tab, run `printf '\033[?1004h'; cat -v`.
2. Switch to another split in the same tab and back. Expect `^[[O` then `^[[I`.
   Unchanged from today.
3. Switch to another tab and back. Expect `^[[O` on leaving and `^[[I` on
   returning. This is the reported bug.
4. Cmd-Tab to another application and back. Expect `^[[O` then `^[[I`. This is
   new behavior.
5. Cleanup: Ctrl-C, then `printf '\033[?1004l'`.
6. Quit and cold-launch montty from the launcher. Expect the active tab's
   focused surface to accept typing with no click.

Exactly one transition per change. No duplicate `ESC[O` when the app is already
inactive and the user also switches tabs; the `focusDidChange` guard and the
policy's single-focused-surface invariant enforce this together.

## Known risk

`MainWindow` rebuilds the split container with `.id(activeTab.id)`
(`MainWindow.swift:94`), so returning to a tab re-inserts its NSViews. If
SwiftUI's `.focused()` claims first responder on the wrong leaf during that
rebuild, `becomeFirstResponder` fires `focusDidChange(true)` on that leaf and the
subsequent sync blurs it again, producing a spurious `ESC[I`/`ESC[O` pair.

No speculative deferral is added for this. Implement the straightforward version,
watch step 3 of the manual acceptance for extra transitions, and add a trailing
next-runloop sync only if the noise actually appears.
