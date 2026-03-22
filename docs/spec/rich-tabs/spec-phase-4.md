# Implementation Spec: Rich Tabs - Phase 4

**Contract**: ./contract.md
**Estimated Effort**: M

## Overview

Redesign the `TabRow` view to display all the rich metadata from Phases 1-3. This phase is primarily visual -- integrating TabInfo, GitInfo, Claude Code detection, and the minimap into a cohesive tab layout that uses the available vertical space well.

## Technical Approach

With 3-8 tabs and a ~600px sidebar height, each tab can be 75-200px tall. The new layout uses this space for:

1. **Primary line**: Tab name (bold) + color indicator
2. **Git context line**: repo name, branch name (smaller text, muted color)
3. **Directory line**: working directory (truncated, muted)
4. **Minimap**: Small split layout visualization (only when tab has splits)
5. **Indicators**: Claude Code session badge (when active)

The layout adapts: git info line is hidden when outside a repo, minimap is hidden for single-pane tabs, Claude Code badge appears/disappears dynamically.

## Feedback Strategy

**Inner-loop command**: `just run`
**Playground**: Running app with multiple tabs in different states
**Why this approach**: This phase is primarily visual layout work. Need to see it rendered.

## File Changes

### Modified Files

| File Path | Changes |
|-----------|---------|
| `Sources/View/TabRow.swift` | Complete redesign with multi-line rich layout |
| `Sources/View/TabSidebar.swift` | Adjust List row height for taller tabs |

## Implementation Details

### TabRow layout

```
+--+-------------------------------+
|  | Tab Name                      |    <- bold, 14pt
|  | repo-name  main               |    <- 11pt, git icon + branch
|  | ~/projects/montty             |    <- 11pt, muted gray
|  |  +----+----+                  |    <- minimap (if splits)
|  |  | *  |    |                  |
|  |  +----+----+                  |
|  |  Claude Code: fixing BCI      |    <- badge (if Claude Code active)
+--+-------------------------------+
```

The left edge is the 4px color indicator bar (existing). Each section is conditional:
- Git line only shows when `tabInfo.gitInfo != nil`
- Directory only shows when `tabInfo.workingDirectory != nil`
- Minimap only shows when `tabInfo.splitCount > 1`
- Claude Code badge only shows when `tabInfo.claudeCode != nil`

### Dynamic row height

Tabs grow/shrink based on content. A tab with no git info, no splits, and no Claude Code is compact (just name + directory). A tab with everything is taller. SwiftUI's List handles variable-height rows.

## Red/Green Tests

No new model tests in this phase (all model logic was tested in Phases 1-3). Visual verification only.

## Verification

- `just build` -- compiles
- `just test` -- all existing tests still pass
- `just run` with various scenarios:
  - Tab in a git repo shows repo name + branch
  - Tab outside a git repo shows only directory
  - Tab with splits shows minimap
  - Tab with Claude Code running shows session badge
  - 8 tabs fit comfortably in the sidebar
  - Single-pane tab is compact
  - Tab with everything visible is readable
