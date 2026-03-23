# Rich Tabs Contract

**Created**: 2026-03-22
**Confidence Score**: 95/100
**Status**: Draft

## Problem Statement

montty's tab sidebar currently shows a user-set name and a single-line working directory. With 3-8 tabs and generous vertical space, there is room for much richer, at-a-glance information: git context, split layout minimap, Claude Code activity indicators, and more. Developers switch between terminal contexts dozens of times per hour -- rich tabs reduce the cognitive cost of "where am I?" to a glance at the sidebar.

Today, the only metadata flowing from terminal panes to tabs is the window title (OSC 0) and working directory (OSC 7). Git branch, repo name, worktree, and running process information require new data collection. The tab UI needs a clean abstraction layer between terminal metadata sources and the visual tab layout, so we can iterate on visual design without coupling to Ghostty internals.

## Goals

1. **Rich tab metadata**: Each tab displays working directory, git repo, git branch, and (when applicable) Claude Code session status -- all derived automatically with zero shell configuration.
2. **Split minimap**: Tabs with splits show a visual minimap of the pane layout with activity indicators.
3. **Clean data contract**: A well-defined `TabInfo` model sits between Ghostty surface metadata and the tab UI, making each layer independently testable.
4. **Always-present minimap**: Every tab shows a colored visual representation of its pane layout. Single-pane tabs are a solid colored block. Splits show the layout structure. Each pane can have its own color (tab color by default, per-pane overrides in future phases via environment variables).
5. **OSC primer**: A reference document explaining OSC escape sequences, how terminals use them, and how montty can leverage them for future extensibility.
6. **Extensibility for future customization**: The architecture supports user-configurable tab templates and per-pane coloring via environment variables, without requiring a rewrite.

## Success Criteria

- [x] Tabs show git repo name and branch when pwd is inside a git repository
- [x] Git info updates when user `cd`s to a different repo
- [x] Tabs show Claude Code session name when Claude Code is running (via terminal title)
- [x] Tabs with splits show a minimap of the split layout
- [x] `TabInfo` model is unit-testable without AppKit or Ghostty dependencies
- [x] Git info derivation is unit-testable (given a path, returns repo/branch/worktree)
- [x] OSC primer document exists at docs/spec/rich-tabs/osc-primer.md
- [x] All existing tests continue to pass
- [x] Tab rendering works correctly with 1, 3, and 8 tabs
- [ ] Claude Code indicator on minimap panes (Phase 5a: presence detection)
- [ ] Claude Code working/waiting state detection via hooks (Phase 5b)

## Testing Philosophy

Red/green testing is a first-class requirement. Every new model type and data derivation must have a failing test written before the implementation. Specifically:

- **TabInfo model**: Tests for each field derivation (git info from pwd, Claude Code detection from title, minimap from split tree). Pure data transforms, no AppKit.
- **GitInfo derivation**: Tests with fixture directories (real .git/HEAD files in temp dirs). Given a path, returns structured git context or nil.
- **Title parsing**: Tests for extracting Claude Code session names from terminal title strings. Pure string parsing.
- **Minimap model**: Tests that a SplitNode tree produces the correct minimap representation. Pure tree-to-layout transform.

Visual rendering (SwiftUI tab layout) is not unit-testable but should be separated from the testable model layer by the TabInfo contract.

## Scope Boundaries

### In Scope

- `TabInfo` model: structured metadata derived from terminal surface properties
- Git info derivation: repo name, branch, worktree from working directory (filesystem reads)
- Claude Code detection: parse terminal title for Claude Code session names
- Split minimap: always-present colored visual of pane layout (solid block for single-pane, structured for splits)
- OSC primer document with links to references
- Auto-derive git info from pwd (no shell config required)
- Fixed tab layout with sensible fallbacks (no user customization in v1)

### Out of Scope

- User-configurable tab templates -- architecture supports it, but not implemented
- Per-tab terminal theming (color-tinted backgrounds) -- future work
- OSC 1337 SetUserVar support -- Ghostty doesn't support it upstream
- Foreground process detection via PTY fd -- GhosttyKit doesn't expose it
- Shell integration hooks for reporting custom metadata
- Claude Code "working" vs "idle" state detection -- Phase 5b via hooks

### Future Considerations

- Template-based tab layout (user-defined format strings)
- OSC 1337 SetUserVar for arbitrary shell-to-tab metadata
- Activity/bell indicators per pane in the minimap
- Per-tab terminal color theming
- Sidebar resize (drag to adjust width)

## Execution Plan

### Dependency Graph

```
OSC Primer (doc only, no code)

Phase 1: TabInfo + GitInfo
  ├── Phase 2: Claude Code detection  (blocked by Phase 1)
  ├── Phase 3: Split minimap          (blocked by Phase 1)
  └── Phase 4: Rich tab UI            (blocked by Phases 1, 2, 3)
```

### Execution Steps

**Strategy**: Hybrid -- Phase 1 is blocking, Phases 2 and 3 are parallelizable, Phase 4 depends on all.

1. ~~**Fix directory restoration** -- quick standalone fix before starting rich tabs~~ DONE
2. ~~**Phase 1** -- TabInfo model + GitInfo derivation~~ DONE
3. ~~**Phases 2 and 3** -- Claude Code detection + Split minimap~~ DONE
4. ~~**Phase 4** -- Rich tab UI~~ DONE
5. **Phase 5a** -- Claude Code presence indicator on minimap (title-based detection)
6. **Phase 5b** -- Claude Code state detection via hooks (working/waiting/idle)
