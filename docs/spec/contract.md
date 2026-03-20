# montty - Contract

## Problem

Terminal multiplexers and tabbed terminals (cmux, iTerm2, etc.) either lack vertical tabs entirely or implement them with too much "smart" behavior: auto-sorting by activity, fixed highlight colors, tiny fonts, and dynamically-changing tab names. For developers running 6-8 terminal sessions across projects and worktrees, the tab sidebar should help orient quickly -- but these behaviors actively hinder that.

Specific pain points (validated by multiple developers):
- No control over tab font size (too small to scan at a glance)
- Tab names change dynamically based on running processes instead of showing the stable workspace/directory
- Tabs auto-sort by activity, so spatial memory is useless
- Active tab is always the same color (blue), regardless of user preference
- No per-tab color coding to visually group or distinguish projects

## Goals

Build "montty" -- a macOS terminal app on top of GhosttyKit (MIT licensed) with:

1. **Vertical tab sidebar** with large, prominent font showing directory/workspace name
2. **Static tab positioning** -- tabs stay where you put them, manual drag-to-reorder only
3. **Per-tab user-assignable colors** with optional auto-color from env/directory
4. **Horizontal and vertical splits** within each tab
5. **Session restore** -- tabs, splits, names, colors, positions survive restart
6. **Standard Ghostty theming** -- reads `~/.config/ghostty/config` for terminal appearance
7. **Per-tab terminal theming** -- each tab can have a color-tinted terminal theme (e.g., red tab gets red-hued terminal colors), applied per-surface via `ghostty_surface_update_config`
7. **Excellent test coverage** on tab model logic with fast local test cycle

## Success Criteria

- [ ] Single window with vertical tab sidebar renders terminal surfaces
- [ ] Tab font is significantly larger than cmux's default; directory name is the primary display
- [ ] Creating 6-8 tabs and switching between them feels instant
- [ ] Tabs never move unless the user drags them
- [ ] Each tab can have a user-assigned color; active tab highlights in that color
- [ ] Horizontal and vertical splits work within any tab
- [ ] Quit and relaunch restores all tabs, splits, names, colors, and positions
- [ ] Tabs with an assigned color tint the terminal theme (background, cursor, etc.) toward that color
- [ ] Unit tests cover tab model (ordering, reorder, color, naming) and split tree (split, close, walk)
- [ ] Session persistence has round-trip encode/decode tests
- [ ] SwiftLint passes with no warnings
- [ ] Full test suite runs in under 10 seconds

## Scope

### In scope
- Single macOS window with vertical tab sidebar (left side)
- Tab operations: create, close, rename, reorder (drag), assign color
- Tab display: large font, directory name prominent, user-assigned color indicator
- Per-tab splits: horizontal and vertical, resize dividers, focus navigation
- Session persistence to JSON file (auto-save + restore on launch)
- Ghostty terminal theming (reads standard config)
- Swift Testing unit tests for all model logic
- SwiftLint for code style
- justfile with setup/build/test/lint recipes

### Out of scope
- Multiple windows (single window only in v1)
- Browser panels, markdown panels, or any non-terminal panel type
- Remote sessions or daemon (cmuxd)
- Analytics, telemetry, or crash reporting
- Auto-update (Sparkle)
- Config file for tab settings (tab state is persisted automatically)
- CLI tool
- iOS/iPadOS support

## Technical Approach

### Starting point
Fresh Xcode project. Copy Ghostty's MIT-licensed Swift binding layer (~8000 lines across ~15 files) for terminal surface rendering. Build our own tab model, sidebar UI, split tree, and session persistence.

### Key dependencies
- **GhosttyKit.xcframework** -- terminal rendering engine, built from Ghostty source via Zig
- **Ghostty Swift bindings** -- copied from `ghostty/macos/Sources/Ghostty/` (MIT)
- **No other runtime dependencies** -- no Sparkle, PostHog, Sentry, Bonsplit

### Architecture layers
1. **GhosttyKit C API** -- `ghostty_app_t`, `ghostty_surface_t`, `ghostty_config_t`
2. **Swift bindings** (copied) -- `Ghostty.App`, `Ghostty.SurfaceView`, `Ghostty.Config`
3. **Tab model** (new) -- `Tab`, `TabStore`, `TabColor`
4. **Split tree** (new) -- `SplitNode` enum, recursive binary tree
5. **Sidebar UI** (new) -- `TabSidebar`, `TabRow`, SwiftUI views
6. **Session persistence** (new) -- `SessionSnapshot`, JSON encode/decode

## Execution Plan

### Dependency Graph

```
Phase 1 (Skeleton)
    |
    v
Phase 2 (Tab model + sidebar)
    |
    v
Phase 3 (Splits)
    |
    v
Phase 4 (Session persistence)
    |
    v
Phase 5 (Polish)
```

All phases are sequential -- each depends on the previous.

### Execution Steps

1. `Phase 1 - Skeleton`: Xcode project, GhosttyKit integration, single terminal in a window
2. `Phase 2 - Tab model + sidebar`: Tab data model, vertical sidebar UI, create/close/switch/reorder/color
3. `Phase 3 - Splits`: Binary split tree, recursive split view, divider resize, focus navigation
4. `Phase 4 - Session persistence`: Codable snapshots, auto-save, restore on launch
5. `Phase 5 - Polish`: Auto-naming, auto-coloring, keyboard shortcuts, SwiftLint, icon
