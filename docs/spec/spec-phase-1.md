# Phase 1: Skeleton -- Get a Terminal Rendering

## Goal

Create an Xcode project that builds against GhosttyKit.xcframework and renders a single interactive terminal in a window. This validates the entire integration pipeline before adding any custom UI.

## Key Reference

See [ghostty-binding-adaptation.md](ghostty-binding-adaptation.md) for detailed file-by-file guidance on which Ghostty Swift bindings to copy, what modifications each file needs, and the expected compilation error sequence.

## Technical Approach

### Project setup

Create `montty.xcodeproj` with three targets:
- `montty` -- the macOS app (minimum deployment: macOS 14.0)
- `montty-unit` -- unit test target using Swift Testing
- `montty-ui` -- UI test target (placeholder for later phases)

The project uses a bridging header to import GhosttyKit's C API.

### Ghostty submodule

Add Ghostty as a git submodule:
```bash
git submodule add https://github.com/ghostty-org/ghostty.git ghostty
```

Then the `just setup` recipe (for subsequent clones and CI) will:
1. Run `git submodule update --init --recursive`
2. Check for `zig` installation
3. Build `GhosttyKit.xcframework` via `zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast`
4. Symlink the framework into the project root

### Copy Swift bindings

Copy these files from `ghostty/macos/Sources/Ghostty/` into `Sources/Ghostty/`:

**Core (required):**
- `Ghostty.App.swift` (2240 lines) -- app lifecycle, runtime callbacks
- `Ghostty.Surface.swift` (~200 lines) -- surface wrapper
- `Ghostty.Config.swift` (922 lines) -- config loading
- `Ghostty.ConfigTypes.swift` -- config enum types
- `Ghostty.Input.swift` (~1314 lines) -- keyboard/mouse input conversion
- `Ghostty.Action.swift` (~300 lines) -- action data models
- `Ghostty.Command.swift` -- shell command types
- `Ghostty.Error.swift` -- error types
- `Ghostty.Event.swift` -- event types
- `Ghostty.Shell.swift` (~30 lines) -- shell selection
- `GhosttyPackage.swift` (~450 lines) -- notifications, helpers, C type extensions
- `GhosttyDelegate.swift` (~11 lines) -- delegate protocol
- `NSEvent+Extension.swift` (~50 lines) -- AppKit event helpers

**Surface rendering (required):**
- `SurfaceView_AppKit.swift` (2341 lines) -- the NSView that renders terminal
- `SurfaceView.swift` (~250 lines) -- SwiftUI wrappers
- `SurfaceScrollView.swift` (~300 lines) -- scroll overlay
- `SurfaceProgressBar.swift` (~100 lines) -- progress indicator
- `SurfaceGrabHandle.swift` (~50 lines) -- resize handle

**Excluded (not needed for v1):**
- `Ghostty.Inspector.swift` -- debug inspector
- `GhosttyPackageMeta.swift` -- Ghostty-specific build metadata
- `FullscreenMode+Extension.swift` -- Ghostty fullscreen modes
- `SurfaceView_UIKit.swift` -- iOS
- `SurfaceView+Image.swift` -- image export
- `SurfaceView+Transferable.swift` -- drag/drop transferable
- `SurfaceDragSource.swift` -- drag source
- `InspectorView.swift` -- inspector UI

### Adaptation of Ghostty.App.swift

This file needs the most modification. The upstream version routes actions through `BaseTerminalController` and posts notifications for the Ghostty macOS app's window management. montty needs to:

1. Remove references to `BaseTerminalController` and Ghostty's own window/tab types
2. Keep the core `ghostty_app_t` lifecycle (init, tick, free)
3. Keep the `ghostty_runtime_config_s` callback setup (wakeup, action, clipboard, close_surface)
4. Route the `action_cb` through a new `MonttyAppDelegate` protocol method instead of dispatching to Ghostty's controller hierarchy
5. Keep config loading (`ghostty_config_load_default_files` for `~/.config/ghostty/config`)

The goal is minimal changes -- keep as much upstream code as possible to make future syncs easier. Mark all modifications with `// MONTTY:` comments.

### App entry point

```
Sources/
  App/
    MonttyApp.swift      -- @main SwiftUI App
    AppDelegate.swift         -- NSApplicationDelegate, owns Ghostty.App
    MainWindow.swift          -- Single NSWindow with terminal content
  Ghostty/
    ... (copied binding files)
```

`AppDelegate` creates the `Ghostty.App` singleton and handles the runtime callbacks. `MainWindow` embeds a single `Ghostty.SurfaceView` via `SurfaceRepresentable` (the SwiftUI wrapper from the copied bindings).

### Build configuration

- Bridging header: `montty-Bridging-Header.h` importing `ghostty.h`
- Framework search paths: include `GhosttyKit.xcframework`
- Signing: development team, sandbox entitlements (network access for terminal)
- `Info.plist`: basic app metadata, bundle ID `com.montty.app`

## File Changes

### New files
| File | Purpose |
|------|---------|
| `montty.xcodeproj/` | Xcode project with 3 targets |
| `montty-Bridging-Header.h` | Imports `ghostty.h` |
| `ghostty.h` | Copied C API header from Ghostty |
| `Sources/App/MonttyApp.swift` | @main SwiftUI app entry |
| `Sources/App/AppDelegate.swift` | NSApplicationDelegate, Ghostty.App owner |
| `Sources/App/MainWindow.swift` | Window hosting terminal surface |
| `Sources/Ghostty/*.swift` | Copied + trimmed binding files (~15 files) |
| `Resources/Info.plist` | App metadata |
| `Resources/montty.entitlements` | Sandbox entitlements |
| `justfile` | Task runner with setup, build, test, lint recipes |
| `.swiftlint.yml` | SwiftLint configuration |
| `.gitignore` | Build artifacts, DerivedData, .DS_Store |
| `Tests/PlaceholderTests.swift` | Verify test target works |

### Modified files
None (fresh project).

## Testing

### Phase 1 tests
- `Tests/PlaceholderTests.swift` -- a single `@Test func appTargetBuilds()` that verifies the test target links and runs. This confirms the Swift Testing setup works.

### Manual verification
- `just setup` completes without errors
- `just build` compiles the app
- Launch the app -- a terminal appears in the window
- Type commands -- input works, output renders
- Ghostty config is loaded (`~/.config/ghostty/config` theming applies)
- `just test` runs and passes

## justfile recipes

```just
# justfile for montty

# Initialize submodules and build GhosttyKit
setup:
    git submodule update --init --recursive
    @command -v zig >/dev/null || { echo "Error: zig not installed. Run: brew install zig"; exit 1; }
    cd ghostty && zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast
    ln -sfn ghostty/macos/GhosttyKit.xcframework GhosttyKit.xcframework
    @echo "Setup complete. Run: just build"

# Build the app
build:
    xcodebuild -project montty.xcodeproj -scheme montty -configuration Debug -destination 'platform=macOS' build

# Run unit tests
test:
    xcodebuild -project montty.xcodeproj -scheme montty-unit -destination 'platform=macOS' test

# Run SwiftLint
lint:
    swiftlint lint --strict
```

## Verification

1. `just setup` -- builds GhosttyKit successfully
2. `just build` -- compiles the app with no errors
3. Launch app from DerivedData -- window appears with terminal
4. Type `echo hello` -- see output rendered with Ghostty theming
5. `just test` -- placeholder test passes
6. `just lint` -- no warnings (once SwiftLint is installed)
