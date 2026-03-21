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
- [x] Integration test: inspect-type + inspect-key + inspect-screen verified
- [x] Integration test: inspect-screenshot saves viewable PNG verified

## Phase 2: Tab Model + Sidebar
- [x] Tab data model (Tab, TabStore, TabColor) with position invariant
- [x] 25 unit tests for model layer (ordering, close, move, rename, color, Codable)
- [x] Vertical tab sidebar (TabSidebar, TabRow, TabContextMenu, TabColorPicker)
- [x] HSplitView layout: sidebar | terminal content
- [x] Multi-surface lifecycle (AppDelegate creates/stores/destroys per tab)
- [x] Title/PWD observation via Combine (auto-updates tab name/directory)
- [x] Ghostty action routing (new_tab, close_tab, goto_tab notifications)
- [x] Tab switching via goto_tab:N actions
- [x] Debug server /surfaces returns tab info (name, color, position, active)
- [x] inspect-action justfile recipe
- [x] Full window screenshots (CGWindowListCreateImage)
- [x] `just check` passes (34 tests, 0 lint violations, build succeeds)
- [x] Drag-to-reorder tabs
- [x] Right-click context menu: rename, set color, close
- [x] Cmd+T / Cmd+W keyboard shortcuts
- [x] Cmd+1-9 tab switching
- [x] Shell exit (ctrl+D) auto-closes tab
- [x] Tab switch refocuses terminal for immediate typing

## Phase 3: Splits
- [x] SplitNode/SplitBranch/SurfaceLeaf data model
- [x] SplitTree pure functions (split, close, find, navigate)
- [x] SplitContainerView recursive SwiftUI view
- [x] SplitDividerView with draggable divider
- [x] Tab model updated (splitRoot + focusedLeafID)
- [x] AppDelegate surface lifecycle for splits
- [x] Ghostty action routing (new_split, close_surface, focus_split)
- [x] Focus management (ghostty_surface_set_focus, visual dimming)
- [x] Spatial navigation (findNeighbor with tree walk)
- [x] Directional split creation (left/up places new pane first)
- [x] Perpendicular position matching in spatial navigation
- [x] Ctrl-key fast path (bypass interpretKeyEvents for ctrl-only input)
- [x] 60 unit tests, SwiftLint passes, build succeeds

## CI
- [x] GitHub Actions ci.yml (test + lint + build on push/PR to main)
- [x] GitHub Actions release.yml (signed DMG on tag push)
- [x] Apple Developer secrets configured in repo

## Phase 4: Session Persistence
(to be detailed when Phase 4 work begins)

## Phase 5: Polish
(to be detailed when Phase 5 work begins)
