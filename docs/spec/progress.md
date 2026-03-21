# montty -- Progress

## Phase 1: Skeleton
- [x] Git submodule added for Ghostty
- [x] GhosttyKit.xcframework builds via `just setup`
- [x] xcodegen project.yml created
- [x] `montty.xcodeproj` generates via `just generate`
- [x] Bridging header and ghostty.h in place
- [x] Ghostty Swift bindings copied (~20 files via `just sync-bindings`)
- [x] Helper dependencies copied (CrossKit, Weak, Cursor, SecureInput, Backport, 10+ extensions)
- [x] Ghostty.App.swift adapted (BaseTerminalController stubs, SplitTree removal)
- [x] SurfaceView_AppKit.swift trimmed (inspector removal, focus-follows-mouse stub)
- [x] SurfaceView.swift trimmed (SecureInputOverlay, iOS blocks)
- [x] SurfaceGrabHandle.swift stubbed (no split drag yet)
- [x] AppDelegate created with full interface for binding compatibility
- [x] MonttyApp.swift entry point with WindowGroup
- [x] MainWindow.swift renders Ghostty.Terminal
- [x] Info.plist and entitlements configured
- [x] `just build` compiles with no errors
- [x] App launches and renders interactive terminal
- [x] Ghostty config theming applies (~/.config/ghostty/config)
- [x] PlaceholderTests.swift passes via `just test`
- [x] SwiftLint passes via `just lint` (Sources/Ghostty excluded)
- [x] .gitignore covers build artifacts
- [x] justfile has setup/build/test/lint/generate/sync-bindings recipes

## Phase 1.5: Debug Server
- [x] DebugServer.swift with Network.framework HTTP server
- [x] Surface discovery via NSWindow view hierarchy walk
- [x] /surfaces endpoint lists all terminal surfaces
- [x] /type endpoint sends text to terminal
- [x] /key endpoint sends key events (return, ctrl+c, etc.)
- [x] /screen endpoint reads visible terminal text
- [x] /screenshot endpoint captures terminal as PNG
- [x] /state endpoint returns terminal metadata
- [x] /action endpoint triggers Ghostty keybind actions
- [x] #if DEBUG compilation guard (excluded from release)
- [x] AppDelegate wires start/stop
- [x] justfile inspect-* recipes
- [x] docs/debug-server.md usage documentation
- [x] CLAUDE.md references debug server
- [x] Unit tests for request parsing and key mapping (9 tests)
- [x] SwiftLint passes
- [ ] Integration test: inspect-type + inspect-key + inspect-screen (needs manual verification)
- [ ] Integration test: inspect-screenshot saves viewable PNG (needs manual verification)

## Phase 2: Tab Model + Sidebar
(to be detailed when Phase 2 work begins)

## Phase 3: Splits
(to be detailed when Phase 3 work begins)

## Phase 4: Session Persistence
(to be detailed when Phase 4 work begins)

## Phase 5: Polish
(to be detailed when Phase 5 work begins)
