# Surface Focus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the terminal keyboard focus on cold launch, and emit DEC mode 1004 focus reports (`ESC[O` / `ESC[I`) when switching tabs or leaving montty for another application.

**Architecture:** Introduce one pure policy function that decides which single surface libghostty should treat as focused, and one applier on `AppDelegate` that is the sole caller of `focusDidChange`. Every path that can change focus (tab switch, split switch, surface creation and close, session restore, window key changes) routes through that applier. This mirrors upstream Ghostty's `BaseTerminalController.syncFocusToSurfaceTree()`.

**Tech Stack:** Swift 5, AppKit + SwiftUI, GhosttyKit C API, Swift Testing, xcodegen, Justfile.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-08-04-surface-focus-design.md`. Read it before starting.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`). Never XCTest.
- Red/green: write the failing test first, watch it fail, then make it pass.
- All new code files start with two `// ABOUTME: ` comment lines.
- SwiftLint runs with `--strict`, so warnings fail. Keep lines under 120 characters.
- `Sources/Ghostty/` is upstream code. This plan makes no changes there. If one becomes necessary, mark it `// MONTTY:`.
- Ghostty C API calls happen on the main actor.
- After adding or removing any file under `Sources/` or `Tests/`, run `just generate` before `just test` or `just build`. xcodegen globs directories, so a new file is invisible to Xcode until the project is regenerated.
- `just check` (test + lint + build) runs as a pre-commit hook. Every commit step in this plan will trigger it.
- **Never run `just stop`.** It kills processes by name and will kill the host montty this session may be running inside. To stop a test instance, quit it from its own menu or `kill <pid>` the specific process you launched.
- Comments state what is true now. No dates, ticket IDs, "currently", or narration of what was tried.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `Sources/Model/SurfaceFocus.swift` (create) | Pure policy: given tabs, active tab, and window key state, return the focus flag for every surface. No AppKit, no Ghostty. |
| `Tests/SurfaceFocusTests.swift` (create) | Unit tests for the policy. |
| `Sources/App/AppDelegate.swift` (modify) | `updateSurfaceFocus(for:)` becomes `syncSurfaceFocus()`; call sites rerouted; launch activation added. Keeps `syncSurfaceFocus` here so the `private surfaces` dictionary stays private. |
| `Sources/App/AppDelegate+Focus.swift` (create) | `NSWindowDelegate` conformance: `windowDidBecomeKey`, `windowDidResignKey`. |
| `Sources/App/AppDelegate+GhosttyActions.swift` (modify) | One call-site substitution in the `ghosttySurfaceFocused` observer. |
| `Sources/App/MainWindow.swift` (modify) | Tab-change handler syncs focus before moving the first responder. |
| `Sources/App/DebugServerHandlers.swift` (modify) | Expose the libghostty `focused` flag on `GET /surfaces` for verification. |

---

### Task 1: Expose the libghostty focus flag on `/surfaces`

Instrument before changing behavior. `GET /surfaces` reports the model-level `focused_in_tab` but not `SurfaceView.focused`, which is the flag that gates the escape-sequence write. `docs/debug-server.md:34` already documents a `focused` field that the code does not send, so this makes the docs true.

**Files:**
- Modify: `Sources/App/DebugServerHandlers.swift:232-237`

**Interfaces:**
- Consumes: nothing.
- Produces: `GET /surfaces` entries gain `"focused": Bool`, the value of `Ghostty.SurfaceView.focused`. Later tasks use `just inspect-surfaces | jq '[.[] | select(.focused)] | length'` to assert exactly one focused surface.

- [ ] **Step 1: Add the field**

In `Sources/App/DebugServerHandlers.swift`, find `addSurfaceViewData` (around line 232):

```swift
    private static func addSurfaceViewData(
        leaf: SurfaceLeaf, appDelegate: AppDelegate, entry: inout [String: Any]
    ) {
        guard let view = appDelegate.surfaceView(for: leaf.surfaceID) else { return }
        entry["title"] = view.title
```

Insert one line after the `title` assignment:

```swift
    private static func addSurfaceViewData(
        leaf: SurfaceLeaf, appDelegate: AppDelegate, entry: inout [String: Any]
    ) {
        guard let view = appDelegate.surfaceView(for: leaf.surfaceID) else { return }
        entry["title"] = view.title
        entry["focused"] = view.focused
```

- [ ] **Step 2: Build**

Run: `just build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Verify the field appears at runtime**

Run:
```bash
just run-bg
sleep 3
just inspect-surfaces | jq '[.[] | {id, tab_position, focused_in_tab, focused}]'
```
Expected: every entry has a `focused` key. On a single-tab app the one surface shows `"focused": true`.

Leave the instance running for later tasks. Do not run `just stop`.

- [ ] **Step 4: Commit**

```bash
git add Sources/App/DebugServerHandlers.swift
git commit -m "debug: report libghostty focus flag on /surfaces"
```

---

### Task 2: Pure surface focus policy

**Files:**
- Create: `Sources/Model/SurfaceFocus.swift`
- Test: `Tests/SurfaceFocusTests.swift`

**Interfaces:**
- Consumes: `Tab` (`Sources/Model/Tab.swift`), `SplitTree.allLeaves(node:)` (`Sources/Model/SplitTree.swift:92`), `SurfaceLeaf` (`Sources/Model/SplitNode.swift:46`).
- Produces:
  ```swift
  enum SurfaceFocus {
      static func plan(tabs: [Tab], activeTabID: UUID?, windowIsKey: Bool) -> [UUID: Bool]
  }
  ```
  The dictionary is keyed by `SurfaceLeaf.surfaceID` (not `leaf.id`) and contains an entry for every surface in every tab. Task 3's applier consumes it.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SurfaceFocusTests.swift`:

```swift
import Foundation
import Testing

struct SurfaceFocusTests {
    /// Adds a second pane to a tab and returns the new pane's surface ID.
    private func addSplit(to tab: Tab) -> UUID {
        let newLeafID = UUID()
        let newSurfaceID = UUID()
        tab.splitRoot = SplitTree.split(
            node: tab.splitRoot,
            leafID: tab.focusedLeafID!,
            orientation: .horizontal,
            newLeafID: newLeafID,
            newSurfaceID: newSurfaceID
        )
        return newSurfaceID
    }

    @Test func focusesTheActiveTabsFocusedPane() {
        let surface = UUID()
        let tab = Tab(surfaceID: surface)

        let plan = SurfaceFocus.plan(tabs: [tab], activeTabID: tab.id, windowIsKey: true)

        #expect(plan[surface] == true)
    }

    @Test func blursEverythingWhenWindowIsNotKey() {
        let surface = UUID()
        let tab = Tab(surfaceID: surface)

        let plan = SurfaceFocus.plan(tabs: [tab], activeTabID: tab.id, windowIsKey: false)

        #expect(plan[surface] == false)
    }

    @Test func blursEverythingWhenNoTabIsActive() {
        let surface = UUID()
        let tab = Tab(surfaceID: surface)

        let plan = SurfaceFocus.plan(tabs: [tab], activeTabID: nil, windowIsKey: true)

        #expect(plan[surface] == false)
    }

    @Test func blursTheFocusedPaneOfABackgroundTab() {
        let activeSurface = UUID()
        let backgroundSurface = UUID()
        let active = Tab(surfaceID: activeSurface)
        let background = Tab(surfaceID: backgroundSurface)

        let plan = SurfaceFocus.plan(
            tabs: [active, background], activeTabID: active.id, windowIsKey: true
        )

        #expect(plan[activeSurface] == true)
        #expect(plan[backgroundSurface] == false)
    }

    @Test func backgroundTabKeepsItsFocusedLeaf() {
        let active = Tab(surfaceID: UUID())
        let background = Tab(surfaceID: UUID())
        let originalLeafID = background.focusedLeafID

        _ = SurfaceFocus.plan(
            tabs: [active, background], activeTabID: active.id, windowIsKey: true
        )

        #expect(background.focusedLeafID == originalLeafID)
    }

    @Test func blursNonFocusedPanesInTheActiveTab() {
        let firstSurface = UUID()
        let tab = Tab(surfaceID: firstSurface)
        let secondSurface = addSplit(to: tab)

        let plan = SurfaceFocus.plan(tabs: [tab], activeTabID: tab.id, windowIsKey: true)

        #expect(plan[firstSurface] == true)
        #expect(plan[secondSurface] == false)
    }

    @Test func blursEveryPaneWhenTabHasNoFocusedLeaf() {
        let surface = UUID()
        let tab = Tab(surfaceID: surface)
        tab.focusedLeafID = nil

        let plan = SurfaceFocus.plan(tabs: [tab], activeTabID: tab.id, windowIsKey: true)

        #expect(plan[surface] == false)
    }

    @Test func includesEverySurfaceInEveryTab() {
        let activeSurface = UUID()
        let backgroundSurface = UUID()
        let active = Tab(surfaceID: activeSurface)
        let background = Tab(surfaceID: backgroundSurface)
        let activeSplit = addSplit(to: active)
        let backgroundSplit = addSplit(to: background)

        let plan = SurfaceFocus.plan(
            tabs: [active, background], activeTabID: active.id, windowIsKey: true
        )

        #expect(plan.count == 4)
        #expect(plan[activeSurface] != nil)
        #expect(plan[activeSplit] != nil)
        #expect(plan[backgroundSurface] != nil)
        #expect(plan[backgroundSplit] != nil)
    }

    @Test func focusesAtMostOneSurface() {
        let tabs = (0..<3).map { _ -> Tab in
            let tab = Tab(surfaceID: UUID())
            _ = addSplit(to: tab)
            return tab
        }

        let plan = SurfaceFocus.plan(
            tabs: tabs, activeTabID: tabs[1].id, windowIsKey: true
        )

        #expect(plan.values.filter { $0 }.count == 1)
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project and run the tests to verify they fail**

Run:
```bash
just generate
xcodebuild -project montty.xcodeproj -scheme montty-unit -destination 'platform=macOS' \
  -only-testing:montty-unit/SurfaceFocusTests test SYMROOT=/tmp/montty-build 2>&1 | tail -30
```
Expected: compile failure, `cannot find 'SurfaceFocus' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Model/SurfaceFocus.swift`:

```swift
// ABOUTME: Pure policy deciding which terminal surface libghostty should treat as
// ABOUTME: focused, given tab state and whether the montty window is key.

import Foundation

enum SurfaceFocus {
    /// Focus state for every surface across every tab, keyed by surface ID.
    ///
    /// A surface is focused only when the window is key, it lives in the active
    /// tab, and it is that tab's focused leaf. Every other surface is blurred,
    /// including the focused leaf of a background tab. Background tabs keep
    /// their `focusedLeafID` so the minimap and re-activation still work.
    static func plan(
        tabs: [Tab],
        activeTabID: UUID?,
        windowIsKey: Bool
    ) -> [UUID: Bool] {
        var plan: [UUID: Bool] = [:]
        for tab in tabs {
            let tabCanHoldFocus = windowIsKey && tab.id == activeTabID
            for leaf in SplitTree.allLeaves(node: tab.splitRoot) {
                plan[leaf.surfaceID] = tabCanHoldFocus && leaf.id == tab.focusedLeafID
            }
        }
        return plan
    }
}
```

- [ ] **Step 4: Regenerate and run the tests to verify they pass**

Run:
```bash
just generate
xcodebuild -project montty.xcodeproj -scheme montty-unit -destination 'platform=macOS' \
  -only-testing:montty-unit/SurfaceFocusTests test SYMROOT=/tmp/montty-build 2>&1 | tail -30
```
Expected: `** TEST SUCCEEDED **` with 9 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/Model/SurfaceFocus.swift Tests/SurfaceFocusTests.swift montty.xcodeproj
git commit -m "feat: pure surface focus policy"
```

---

### Task 3: Route every focus change through one applier

This is the task that fixes the reported tab-switch bug. `updateSurfaceFocus(for:)` only ever touched one tab, so switching tabs left the outgoing surface with `focused == true`. `focusDidChange` early-returns on an unchanged flag (`Sources/Ghostty/SurfaceView_AppKit.swift:428`), so neither surface wrote anything.

**Files:**
- Modify: `Sources/App/AppDelegate.swift` (replace `updateSurfaceFocus(for:)` at 272-283; call sites at 263, 542-544; add calls in `createTab` and `closeTab`)
- Modify: `Sources/App/AppDelegate+GhosttyActions.swift:101`
- Modify: `Sources/App/MainWindow.swift:61-68`

**Interfaces:**
- Consumes: `SurfaceFocus.plan(tabs:activeTabID:windowIsKey:)` from Task 2.
- Produces: `AppDelegate.syncSurfaceFocus()`, internal, no arguments, main-actor only. It is the only code in montty permitted to call `Ghostty.SurfaceView.focusDidChange`. Task 4 calls it from the window delegate.

- [ ] **Step 1: Replace `updateSurfaceFocus(for:)` with `syncSurfaceFocus()`**

In `Sources/App/AppDelegate.swift`, replace this method (lines 272-283):

```swift
    /// Update focus state for all surfaces in a tab so only the focused
    /// pane has an active cursor and accepts key equivalents.
    func updateSurfaceFocus(for tab: Tab) {
        let focusedSurfaceID = tab.focusedSurfaceID
        for leaf in SplitTree.allLeaves(node: tab.splitRoot) {
            guard let view = surfaces[leaf.surfaceID] else { continue }
            let shouldFocus = leaf.surfaceID == focusedSurfaceID
            // Use focusDidChange to update both the Swift-side focused
            // flag and the C-side ghostty_surface_set_focus.
            view.focusDidChange(shouldFocus)
        }
    }
```

with:

```swift
    /// Push the focus policy out to every surface in every tab. The only place
    /// montty calls `focusDidChange`, which updates both the Swift-side flag and
    /// the C-side `ghostty_surface_set_focus`.
    ///
    /// Blurs run before focuses. libghostty writes the DEC mode 1004 reports in
    /// call order, and the outgoing surface must see its blur before the
    /// incoming surface sees its focus.
    func syncSurfaceFocus() {
        let plan = SurfaceFocus.plan(
            tabs: tabStore.tabs,
            activeTabID: tabStore.activeTabID,
            windowIsKey: window?.isKeyWindow ?? false
        )
        for (surfaceID, focused) in plan where !focused {
            surfaces[surfaceID]?.focusDidChange(false)
        }
        for (surfaceID, focused) in plan where focused {
            surfaces[surfaceID]?.focusDidChange(true)
        }
    }
```

- [ ] **Step 2: Reroute `setFocusedLeaf`**

In `Sources/App/AppDelegate.swift`, in `setFocusedLeaf(_:in:)` (around line 261), change:

```swift
        tab.focusedLeafID = leafID
        updateSurfaceFocus(for: tab)
```

to:

```swift
        tab.focusedLeafID = leafID
        syncSurfaceFocus()
```

- [ ] **Step 3: Reroute session restore**

In `Sources/App/AppDelegate.swift`, in `restoreSession`'s deferred block (around line 542), change:

```swift
            for tab in self.tabStore.tabs {
                self.updateSurfaceFocus(for: tab)
            }
```

to:

```swift
            self.syncSurfaceFocus()
```

This also fixes restore marking every tab's focused surface as focused.

- [ ] **Step 4: Sync after creating and closing tabs**

In `Sources/App/AppDelegate.swift`, at the end of `createTab()` (around line 183), change:

```swift
        // Watch for title and PWD changes from this surface
        observeSurface(surfaceView, tab: tab)
    }
```

to:

```swift
        // Watch for title and PWD changes from this surface
        observeSurface(surfaceView, tab: tab)

        // A surface is born with `focused == true`, so blur the tabs it displaced.
        syncSurfaceFocus()
    }
```

In `closeTab(id:)` (around line 193), change:

```swift
        tabStore.close(id: id)

        // If no tabs remain, quit
        if tabStore.tabs.isEmpty {
            NSApplication.shared.terminate(nil)
        }
    }
```

to:

```swift
        tabStore.close(id: id)

        // If no tabs remain, quit
        if tabStore.tabs.isEmpty {
            NSApplication.shared.terminate(nil)
            return
        }
        syncSurfaceFocus()
    }
```

`splitSurface(direction:)` needs no change: it ends by calling `setFocusedLeaf`, which now syncs.

- [ ] **Step 5: Reroute the surface-focused observer**

In `Sources/App/AppDelegate+GhosttyActions.swift`, in `observeSurfaceFocus` (line 101), change:

```swift
            tab.focusedLeafID = leaf.id
            self.updateSurfaceFocus(for: tab)
```

to:

```swift
            tab.focusedLeafID = leaf.id
            self.syncSurfaceFocus()
```

The observer's existing `tab.focusedLeafID != leaf.id` guard (line 98) and `focusDidChange`'s unchanged-flag guard together stop this from looping.

- [ ] **Step 6: Sync on tab switch**

In `Sources/App/MainWindow.swift`, replace the handler at lines 61-68:

```swift
        .onChange(of: tabStore.activeTabID) { _, newID in
            guard let newID = newID,
                  let tab = tabStore.tabs.first(where: { $0.id == newID }),
                  let surfaceID = tab.focusedSurfaceID,
                  let surfaceView = appDelegate.surfaceView(for: surfaceID) else { return }
            Ghostty.moveFocus(to: surfaceView)
            updateWindowTitle(tab: tab)
        }
```

with:

```swift
        .onChange(of: tabStore.activeTabID) { _, newID in
            // Sync before the guard so the outgoing tab blurs even when the
            // incoming tab has no surface view yet.
            appDelegate.syncSurfaceFocus()
            guard let newID = newID,
                  let tab = tabStore.tabs.first(where: { $0.id == newID }),
                  let surfaceID = tab.focusedSurfaceID,
                  let surfaceView = appDelegate.surfaceView(for: surfaceID) else { return }
            Ghostty.moveFocus(to: surfaceView)
            updateWindowTitle(tab: tab)
        }
```

- [ ] **Step 7: Confirm no callers of the old method remain**

Run: `grep -rn "updateSurfaceFocus" Sources/ Tests/`
Expected: no output.

- [ ] **Step 8: Build and run the full suite**

Run: `just test && just lint && just build`
Expected: `** TEST SUCCEEDED **`, no lint output, `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Verify the tab-switch fix by hand**

Restart the test instance so it picks up the new build:
```bash
just run-bg
sleep 3
```

Create a second tab (Cmd+T in the app window), then in the first tab's terminal run:
```bash
printf '\033[?1004h'; cat -v
```

Now, in the app:
1. Switch to a split in the same tab and back. Expect `^[[O` then `^[[I`. This worked before and must still work.
2. Switch to the other tab and back. Expect `^[[O` on leaving and `^[[I` on returning. **This is the bug being fixed.**
3. Confirm exactly one transition per switch, with no extra `^[[I^[[O` pairs. If extra pairs appear, see "Known risk" below.

Cleanup in the terminal: Ctrl-C, then `printf '\033[?1004l'`.

Also confirm the invariant across tabs:
```bash
just inspect-surfaces | jq '[.[] | select(.focused)] | length'
```
Expected: `1`.

And confirm the minimap still marks the right pane: switch to a tab whose second split was active, and check that the second split is highlighted and takes keystrokes.

- [ ] **Step 10: Commit**

```bash
git add Sources/App/AppDelegate.swift Sources/App/AppDelegate+GhosttyActions.swift Sources/App/MainWindow.swift
git commit -m "fix: emit focus reports on tab switch

Route every focus change through a single syncSurfaceFocus() that
applies the SurfaceFocus policy across all tabs. Tab switches left the
outgoing surface marked focused, so neither surface wrote its DEC mode
1004 report."
```

---

### Task 4: Blur when the window stops being key

Montty assigns no `NSWindowDelegate`, so nothing observes window key changes. The app-level path does not compensate: `ghostty_app_set_focus` reaches `App.focusEvent` (`ghostty/src/App.zig:310`), which only sets a flag and never writes an escape sequence. Leaving montty for another application therefore emits no blur today.

**Files:**
- Create: `Sources/App/AppDelegate+Focus.swift`
- Modify: `Sources/App/AppDelegate.swift` (`applicationDidFinishLaunching`, around line 92-94)

**Interfaces:**
- Consumes: `AppDelegate.syncSurfaceFocus()` from Task 3, `AppDelegate.surfaceView(for:)` (`AppDelegate.swift:285`), `AppDelegate.window`, `TabStore.activeTab`.
- Produces: `AppDelegate: NSWindowDelegate` conformance. No new API for later tasks.

- [ ] **Step 1: Create the window delegate extension**

Create `Sources/App/AppDelegate+Focus.swift`:

```swift
// ABOUTME: NSWindowDelegate conformance that keeps libghostty surface focus in
// ABOUTME: step with the window's key state.

import Cocoa

extension AppDelegate: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        // If the window itself is first responder, no surface will accept
        // typing. Hand focus back to the active tab's pane.
        if let window, window.firstResponder === window,
           let surfaceID = tabStore.activeTab?.focusedSurfaceID,
           let surfaceView = surfaceView(for: surfaceID) {
            DispatchQueue.main.async {
                Ghostty.moveFocus(to: surfaceView)
            }
        }

        // Becoming key races responder updates, so let the responder chain
        // settle before reading isKeyWindow and firstResponder.
        DispatchQueue.main.async { [weak self] in
            self?.syncSurfaceFocus()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        syncSurfaceFocus()
    }
}
```

- [ ] **Step 2: Assign the delegate**

In `Sources/App/AppDelegate.swift`, in `applicationDidFinishLaunching`, change:

```swift
        window.contentView = hostingView
        window.title = "Montty"
        window.makeKeyAndOrderFront(nil)
```

to:

```swift
        window.contentView = hostingView
        window.title = "Montty"
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
```

- [ ] **Step 3: Build and run the full suite**

Run: `just generate && just test && just lint && just build`
Expected: `** TEST SUCCEEDED **`, no lint output, `** BUILD SUCCEEDED **`.

`just generate` is required here because `AppDelegate+Focus.swift` is a new file.

- [ ] **Step 4: Verify application-level blur by hand**

```bash
just run-bg
sleep 3
```

In a montty terminal run:
```bash
printf '\033[?1004h'; cat -v
```

1. Cmd-Tab to another application. Expect `^[[O`.
2. Cmd-Tab back to montty. Expect `^[[I`.
3. Cmd-H to hide montty, then reactivate. Expect `^[[O` then `^[[I`.
4. Repeat the Task 3 step 9 checks (split switch, tab switch). They must still produce exactly one transition each.
5. With montty in the background, confirm the invariant:
   ```bash
   just inspect-surfaces | jq '[.[] | select(.focused)] | length'
   ```
   Expected: `0`.
6. Bring montty forward and re-run the same command. Expected: `1`.

Cleanup in the terminal: Ctrl-C, then `printf '\033[?1004l'`.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/AppDelegate+Focus.swift Sources/App/AppDelegate.swift montty.xcodeproj
git commit -m "fix: emit focus reports when the window gains or loses key

Montty had no NSWindowDelegate, and ghostty_app_set_focus only sets an
app-level flag without writing the mode 1004 report, so leaving montty
for another app emitted nothing."
```

---

### Task 5: Give the terminal keyboard focus on cold launch

`applicationDidFinishLaunching` orders the window front but never activates the application, and nothing makes the active tab's surface first responder after restore lays out the view hierarchy.

**Files:**
- Modify: `Sources/App/AppDelegate.swift` (`applicationDidFinishLaunching` around line 94; `restoreSession`'s deferred block around line 533-545)

**Interfaces:**
- Consumes: `AppDelegate.syncSurfaceFocus()` from Task 3, `Ghostty.moveFocus(to:)` (`Sources/Ghostty/SurfaceView.swift:1135`).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Activate the application on launch**

In `Sources/App/AppDelegate.swift`, in `applicationDidFinishLaunching`, change:

```swift
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
```

to:

```swift
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
```

Use `NSApp.activate()`, not the deprecated `activate(ignoringOtherApps:)`. The shipped deployment target is macOS 26.

- [ ] **Step 2: Move the first responder to the active surface after restore**

In `Sources/App/AppDelegate.swift`, in `restoreSession`'s deferred block, change:

```swift
            self.syncSurfaceFocus()
        }
    }
```

to:

```swift
            self.syncSurfaceFocus()
            if let surfaceID = self.tabStore.activeTab?.focusedSurfaceID,
               let surfaceView = self.surfaces[surfaceID] {
                Ghostty.moveFocus(to: surfaceView)
            }
        }
    }
```

- [ ] **Step 3: Move the first responder for the fresh-tab launch path**

`createTab()` runs when there is no saved session, before the view hierarchy exists, so its surface view has no window yet. `Ghostty.moveFocus` reschedules itself until the view is attached, so calling it here is safe.

In `Sources/App/AppDelegate.swift`, in `applicationDidFinishLaunching`, change:

```swift
        // Restore previous session or create a fresh tab
        if let snapshot = sessionStore.load() {
            restoreSession(snapshot)
        } else {
            createTab()
        }
```

to:

```swift
        // Restore previous session or create a fresh tab
        if let snapshot = sessionStore.load() {
            restoreSession(snapshot)
        } else {
            createTab()
            if let surfaceID = tabStore.activeTab?.focusedSurfaceID,
               let surfaceView = surfaceView(for: surfaceID) {
                Ghostty.moveFocus(to: surfaceView)
            }
        }
```

- [ ] **Step 4: Build and run the full suite**

Run: `just test && just lint && just build`
Expected: `** TEST SUCCEEDED **`, no lint output, `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Verify cold launch by hand**

Quit the test instance from its own menu (Cmd+Q in that window), not `just stop`.

Then launch it the way the bug reproduces, from the Mac launcher, and immediately type without clicking. Expect the characters to appear in the active tab's focused pane.

Test both launch paths:
1. **Restored session:** quit with several tabs open, relaunch, type immediately. Characters land in the tab that was active at quit, in the pane that was focused there.
2. **Fresh session:** move the session file aside, relaunch, type immediately. Characters land in the single new tab.
   ```bash
   mv ~/Library/Application\ Support/montty/session.json /tmp/montty-session-backup.json
   ```
   Launch, verify, quit, then restore it:
   ```bash
   mv /tmp/montty-session-backup.json ~/Library/Application\ Support/montty/session.json
   ```
   Restore it before doing anything else. The running app auto-saves every 8 seconds and will overwrite the file with the fresh single-tab session if it is left running.

Also re-confirm the paths that already worked and must not regress: Cmd-Tab back into a running montty, and clicking the Dock icon.

- [ ] **Step 6: Commit**

```bash
git add Sources/App/AppDelegate.swift
git commit -m "fix: focus the active terminal surface on cold launch

Nothing activated the app or set a first responder at launch, so the
window appeared without accepting keystrokes until clicked."
```

---

### Task 6: Update the debug server docs

**Files:**
- Modify: `docs/debug-server.md` (the `GET /surfaces` response block around line 28-38)

**Interfaces:**
- Consumes: the `focused` field added in Task 1.
- Produces: nothing.

- [ ] **Step 1: Make the documented response match what the code sends**

`docs/debug-server.md` already lists `focused` but omits the tab fields the endpoint has sent for some time. Replace the response block:

```json
[
  {
    "id": "A1B2C3D4-...",
    "title": "zsh",
    "pwd": "/Users/ted/montty",
    "focused": true,
    "size": {"rows": 24, "cols": 80, "width_px": 1200, "height_px": 800}
  }
]
```

with:

```json
[
  {
    "id": "A1B2C3D4-...",
    "leaf_id": "E5F6A7B8-...",
    "tab_id": "C9D0E1F2-...",
    "tab_name": "montty",
    "tab_position": 0,
    "tab_color": "blue",
    "active": true,
    "focused_in_tab": true,
    "focused": true,
    "split_count": 1,
    "title": "zsh",
    "pwd": "/Users/ted/montty",
    "size": {"rows": 24, "cols": 80, "width_px": 1200, "height_px": 800}
  }
]
```

Add below the block:

```markdown
`focused_in_tab` is montty's model state: which pane the tab will focus when it
becomes active. `focused` is what libghostty believes, and it is true for at most
one surface across the whole app. It is false for every surface while the montty
window is not key.
```

- [ ] **Step 2: Verify the documented shape against the running app**

Run: `just inspect-surfaces | jq '.[0] | keys'`
Expected: the keys listed in the doc block (optional keys `directory_name`, `git`, and `claude_code` appear only when those apply).

- [ ] **Step 3: Commit**

```bash
git add docs/debug-server.md
git commit -m "docs: document the /surfaces focus fields"
```

---

## Known risk

`MainWindow` rebuilds the split container with `.id(activeTab.id)` (`Sources/App/MainWindow.swift:94`), so returning to a tab re-inserts its NSViews. If SwiftUI's `.focused()` claims first responder on the wrong leaf during that rebuild, `becomeFirstResponder` fires `focusDidChange(true)` on that leaf and the following sync blurs it again, producing a spurious `^[[I^[[O` pair.

Do not add deferral for this preemptively. Task 3 step 9 watches for it. If extra transitions appear, add a trailing next-runloop sync to the tab-change handler:

```swift
        .onChange(of: tabStore.activeTabID) { _, newID in
            appDelegate.syncSurfaceFocus()
            guard let newID = newID,
                  let tab = tabStore.tabs.first(where: { $0.id == newID }),
                  let surfaceID = tab.focusedSurfaceID,
                  let surfaceView = appDelegate.surfaceView(for: surfaceID) else { return }
            Ghostty.moveFocus(to: surfaceView)
            updateWindowTitle(tab: tab)
            DispatchQueue.main.async { appDelegate.syncSurfaceFocus() }
        }
```

Report it if this proves necessary. It means the responder chain is fighting the policy, and the durable fix may be to stop tearing down the container on every tab switch.

## Acceptance

With mode 1004 enabled (`printf '\033[?1004h'; cat -v`):

| Action | Expected |
| --- | --- |
| Switch split within a tab, and back | `^[[O` then `^[[I` (unchanged) |
| Switch to another tab, and back | `^[[O` then `^[[I` (fixed) |
| Cmd-Tab to another app, and back | `^[[O` then `^[[I` (new) |
| Any of the above | exactly one transition, blur before focus |
| Cold launch from the Mac launcher | active tab's focused pane accepts typing with no click |
| Cmd-Tab or Dock click into a running montty | unchanged, still accepts typing |
| Switch back to a tab | the minimap-marked pane is the one that gets focus |

At any moment, `just inspect-surfaces | jq '[.[] | select(.focused)] | length'` returns `1` when montty is frontmost and `0` when it is not.
