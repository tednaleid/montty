# Ghostty Binding Adaptation Guide

Reference document for Phase 1. Covers what to copy from Ghostty's Swift bindings and what needs modification.

## Source location

The Ghostty submodule is at `ghostty/`. The Swift bindings live in:
```
ghostty/macos/Sources/Ghostty/
```

## Files to copy as-is (no modifications needed)

These files are self-contained and work without changes:

| File | Lines | Purpose |
|------|-------|---------|
| `Ghostty.Surface.swift` | ~200 | Wrapper around `ghostty_surface_t` |
| `Ghostty.Input.swift` | ~1314 | Keyboard/mouse input conversion tables |
| `Ghostty.Action.swift` | ~300 | Action data model structs |
| `Ghostty.Command.swift` | ~30 | Shell command enum |
| `Ghostty.Error.swift` | ~20 | Error types |
| `Ghostty.Event.swift` | ~20 | ComparableKeyEvent |
| `Ghostty.Shell.swift` | ~30 | Shell selection |
| `GhosttyDelegate.swift` | ~11 | `GhosttyAppDelegate` protocol (just `findSurface(forUUID:)`) |
| `NSEvent+Extension.swift` | ~50 | AppKit event helpers |
| `SurfaceScrollView.swift` | ~300 | Scroll overlay for terminal |
| `SurfaceProgressBar.swift` | ~100 | Progress indicator |
| `SurfaceGrabHandle.swift` | ~50 | Resize grab handle |

## Files to copy with minor trimming

### GhosttyPackage.swift (~450 lines)

Contains notification names, C type extensions, and helper types used by every other file. Copy as-is. If it references `GhosttyPackageMeta` (build metadata), remove that import -- montty won't have that file.

### Ghostty.Config.swift (922 lines)

Wraps `ghostty_config_t`. The config loading code is essential:
- `ghostty_config_new()` / `ghostty_config_load_default_files()` / `ghostty_config_finalize()`
- This is how `~/.config/ghostty/config` gets loaded

It has ~100 computed properties for config values (fonts, colors, window settings, etc.). Keep all of them for now -- they're read-only accessors and won't cause compilation issues. Trim later if needed.

### Ghostty.ConfigTypes.swift

Enum types referenced by Config.swift. Copy alongside it.

### SurfaceView.swift (~250 lines)

SwiftUI wrappers: `SurfaceRepresentable` (NSViewRepresentable) and `SurfaceWrapper`. These are what embed the terminal NSView into SwiftUI. Copy as-is, but:
- Remove any `#if os(iOS)` blocks
- Remove references to `InspectorView` if present

### SurfaceView_AppKit.swift (2341 lines)

The big one -- the NSView subclass that handles all terminal rendering and input. This is the file you do NOT want to rewrite. Copy as-is, but:
- Remove references to `Ghostty.Inspector` / `InspectorView` (search for `inspector`)
- Remove the `SurfaceDragSource` integration if it causes compilation issues (drag source for terminal text selection)
- The file uses `GhosttyPackage.swift` notification names extensively -- make sure that file is copied first

## Files to copy with significant adaptation

### Ghostty.App.swift (2240 lines)

This is the core runtime integration file. It manages `ghostty_app_t` and dispatches all actions from the terminal engine back to the UI. **This is the only file that needs significant changes.**

#### What to keep unchanged
- Lines 1-78: The `Ghostty.App` class definition, `init()`, `ghostty_runtime_config_s` setup, `ghostty_app_new()` call. This is the core lifecycle.
- The `GhosttyAppDelegate` protocol (line 5-11) -- montty's AppDelegate conforms to this.
- `wakeup_cb`, `read_clipboard_cb`, `write_clipboard_cb`, `close_surface_cb` callbacks -- these are terminal engine plumbing.
- `configReload()`, `configChange()`, `colorChange()` -- config hot-reload support.
- Surface-level actions that post notifications: `setTitle`, `pwdChanged`, `setCellSize`, `rendererHealth`, `keySequence`, `progressReport`, `scrollbar`, `startSearch`, `endSearch`, `searchTotal`, `searchSelected`.

#### What needs adaptation in the action dispatch (line 475-677)

The `action()` static method is a big switch statement dispatching ~40 action types. For each action, it resolves the target surface and then calls a private static method. Many of these methods cast `window.windowController as? BaseTerminalController` -- **this is the main thing that breaks**, because montty has no `BaseTerminalController`.

**Actions montty needs (route to your own AppDelegate/TabStore):**
- `GHOSTTY_ACTION_NEW_TAB` (line 494) -- create a new tab
- `GHOSTTY_ACTION_NEW_SPLIT` (line 497) -- split current pane
- `GHOSTTY_ACTION_CLOSE_TAB` (line 500) -- close current tab
- `GHOSTTY_ACTION_MOVE_TAB` (line 509) -- reorder tab
- `GHOSTTY_ACTION_GOTO_TAB` (line 512) -- switch to tab by index
- `GHOSTTY_ACTION_GOTO_SPLIT` (line 515) -- navigate between splits
- `GHOSTTY_ACTION_RESIZE_SPLIT` (line 521) -- resize split divider
- `GHOSTTY_ACTION_EQUALIZE_SPLITS` (line 524) -- equalize split sizes
- `GHOSTTY_ACTION_SET_TITLE` (line 539) -- update tab auto-name
- `GHOSTTY_ACTION_PWD` (line 548) -- update working directory
- `GHOSTTY_ACTION_CONFIG_CHANGE` (line 2144) -- config hot-reload
- `GHOSTTY_ACTION_OPEN_CONFIG` (line 551) -- open config in editor

**Actions to stub out or ignore (not needed for montty v1):**
- `GHOSTTY_ACTION_NEW_WINDOW` -- single window app
- `GHOSTTY_ACTION_CLOSE_WINDOW` / `CLOSE_ALL_WINDOWS` -- single window
- `GHOSTTY_ACTION_TOGGLE_FULLSCREEN` -- can add later
- `GHOSTTY_ACTION_INSPECTOR` / `RENDER_INSPECTOR` -- no inspector
- `GHOSTTY_ACTION_DESKTOP_NOTIFICATION` -- can add later
- `GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM` -- can add later
- `GHOSTTY_ACTION_FLOAT_WINDOW` -- not applicable
- `GHOSTTY_ACTION_TOGGLE_QUICK_TERMINAL` -- not applicable
- `GHOSTTY_ACTION_TOGGLE_VISIBILITY` -- not applicable
- `GHOSTTY_ACTION_TOGGLE_COMMAND_PALETTE` -- not applicable
- `GHOSTTY_ACTION_CHECK_FOR_UPDATES` -- no Sparkle
- `GHOSTTY_ACTION_COPY_TITLE_TO_CLIPBOARD` -- can add later
- `GHOSTTY_ACTION_PROMPT_TITLE` -- can add later
- `GHOSTTY_ACTION_SET_TAB_TITLE` -- can add later

**Recommended approach:** Rather than gutting the action dispatch, create a `MonttyActionHandler` protocol:

```swift
protocol MonttyActionHandler: AnyObject {
    func handleNewTab()
    func handleNewSplit(surface: Ghostty.SurfaceView, direction: ghostty_action_split_direction_e)
    func handleCloseTab(surface: Ghostty.SurfaceView)
    func handleGotoTab(tab: ghostty_action_goto_tab_e)
    func handleGotoSplit(direction: ghostty_action_goto_split_e)
    func handleResizeSplit(resize: ghostty_action_resize_split_s)
    func handleSetTitle(surface: Ghostty.SurfaceView, title: String)
    func handlePwdChanged(surface: Ghostty.SurfaceView, pwd: String)
}
```

Then in the `action()` switch, replace the `BaseTerminalController` casts with calls to this handler. Unneeded actions return `false` (unhandled). Mark all changes with `// MONTTY:` comments so future Ghostty upstream syncs are easier.

#### Surface resolution pattern

Many action handlers start with this pattern to find the target surface:
```swift
guard case let target = target,
      target.tag == GHOSTTY_TARGET_SURFACE,
      let surface = target.target.surface,
      let surfaceView = Unmanaged<Ghostty.SurfaceView>
          .fromOpaque(surface)
          .takeUnretainedValue() as? Ghostty.SurfaceView
else { return }
```

This pattern works unchanged in montty. The `Ghostty.SurfaceView` reference is the same class from the copied bindings.

## Files to NOT copy

| File | Reason |
|------|--------|
| `Ghostty.Inspector.swift` | Debug inspector, not needed |
| `GhosttyPackageMeta.swift` | Ghostty build metadata (version, commit) |
| `FullscreenMode+Extension.swift` | Ghostty fullscreen modes |
| `SurfaceView_UIKit.swift` | iOS only |
| `SurfaceView+Image.swift` | Image export from terminal |
| `SurfaceView+Transferable.swift` | Drag/drop transferable conformance |
| `SurfaceDragSource.swift` | Drag source for text selection |
| `InspectorView.swift` | Inspector UI |

## Bridging header

Copy `ghostty.h` from `ghostty/include/ghostty.h` (in the submodule). The bridging header is just:

```c
#import "ghostty.h"
```

## GhosttyKit.xcframework

Built from the ghostty submodule:
```bash
cd ghostty && zig build -Demit-xcframework=true \
    -Dxcframework-target=universal -Doptimize=ReleaseFast
```

Output lands at `ghostty/macos/GhosttyKit.xcframework`. Symlink it to the project root.

## Compilation order

When first getting things to compile, expect errors in this order:
1. Missing `GhosttyKit` module -- framework not linked
2. Missing `ghostty.h` types -- bridging header not configured
3. `GhosttyPackage.swift` references to `GhosttyPackageMeta` -- remove that import
4. `Ghostty.App.swift` references to `BaseTerminalController` -- the main adaptation work
5. `SurfaceView_AppKit.swift` references to `Inspector` -- remove those blocks
6. Various `#if os(iOS)` blocks if not stripped -- remove them

The goal is to get `Ghostty.App` initializing and one `SurfaceView` rendering before wiring up any action handling. A terminal that renders and accepts input but ignores keybinding actions (new tab, split, etc.) is the Phase 1 milestone.
