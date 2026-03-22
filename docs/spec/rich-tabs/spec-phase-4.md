# Implementation Spec: Rich Tabs - Phase 4

**Contract**: ./contract.md
**Estimated Effort**: M

## Overview

Redesign the `TabRow` view to display all the rich metadata from Phases 1-3. This phase is primarily visual -- integrating TabInfo, GitInfo, Claude Code detection, and the minimap into a cohesive tab layout that uses the available vertical space well.

## Technical Approach

Tabs are the primary navigation and context tool in montty. With 3-8 tabs on a 1200px+ tall sidebar, each tab can be 150-400px tall -- far more space than traditional terminal tabs. The entire purpose of this app is helping users understand "where they are" at a glance, so tabs should be richly informative rather than compact.

The layout uses this generous space for:

1. **Primary line**: Tab name (bold) + color indicator
2. **Git context line**: repo name, branch name (smaller text, muted color)
3. **Directory line**: working directory (truncated, muted)
4. **Minimap**: Visual representation of the tab's pane layout, always shown (even for single-pane tabs). Each pane in the minimap is a colored rectangle -- the tab's color by default, with per-pane color overrides possible via environment variables (future).
5. **Indicators**: Claude Code session badge (when active)

The minimap is always present as the tab's visual identity. Panes are muted/low-alpha colored rectangles. Only the focused pane gets a bright colored border -- mirroring the real app's focus border around the active split. This means the minimap visually communicates both layout and focus at a glance.

Claude Code activity renders as small symbols overlaid on the relevant minimap pane: muted when working (does not need attention), brighter when waiting for a response (needs attention). This is explicitly designed for iteration -- the symbols and intensity will be tuned over time.

Per-pane color overrides (driven by environment variables) are supported by the model but not populated in v1. See docs/spec/spec-phase-5.md for the per-tab theming vision.

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
|  |                               |
|  |  +====+------+               |    <- minimap (always shown)
|  |  ||   |      |               |    <- focused pane: bright border
|  |  ||   | [~]  |               |    <- [~] = Claude waiting indicator
|  |  +====+------+               |
|  |                               |
+--+-------------------------------+

Minimap key:
  ==== bright border = focused pane
  ---- muted border = unfocused pane
  [~]  Claude Code waiting for response (brighter)
  [.]  Claude Code working (muted, subtle)
```

The left edge is the 4px color indicator bar (existing). Each section is conditional:
- Git line only shows when `tabInfo.gitInfo != nil`
- Directory only shows when `tabInfo.workingDirectory != nil`
- Minimap always shows (single-pane tabs get a solid colored block)
- Claude Code badge only shows when `tabInfo.claudeCode != nil`

### Dynamic row height

Every tab always shows the minimap -- it's the tab's visual identity. Rows vary slightly based on whether git info and Claude Code badges are present, but the minimap is never hidden. SwiftUI's List handles variable-height rows.

## Red/Green Tests

No new model tests in this phase (all model logic was tested in Phases 1-3). Visual verification only.

## Verification

- `just build` -- compiles
- `just test` -- all existing tests still pass
- `just run` with various scenarios:
  - Tab in a git repo shows repo name + branch
  - Tab outside a git repo shows only directory
  - Tab with splits shows minimap with pane layout
  - Single-pane tab shows colored minimap block
  - Tab with Claude Code running shows session badge
  - 8 tabs fit comfortably in the sidebar
  - Tab with everything visible is readable
