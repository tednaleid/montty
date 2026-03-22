# Implementation Spec: Rich Tabs - Phase 3

**Contract**: ./contract.md
**Estimated Effort**: M

## Overview

Add a split minimap model and SwiftUI rendering. Every tab shows a visual representation of its pane layout in the sidebar -- a solid colored block for single-pane tabs, a structured layout for splits. The minimap is always present because it serves as the tab's visual identity. Each pane in the minimap can have its own color (tab's color by default, with per-pane overrides planned for future phases). The minimap model is a pure tree-to-layout transform, testable without UI.

## Technical Approach

`SplitMinimap` is a value type computed from a `SplitNode` tree. It produces a list of `MinimapPane` rects (normalized 0-1 coordinates) representing the visual layout. The SwiftUI rendering draws these rects in a small fixed-size area within the tab row.

The model layer is pure and testable. The view layer is a simple GeometryReader that maps normalized rects to actual pixels.

## Feedback Strategy

**Inner-loop command**: `just test`
**Playground**: Test suite for model; `just run` for visual tuning
**Why this approach**: Minimap model is pure data transform. Visual rendering requires manual checking.

## File Changes

### New Files

| File Path | Purpose |
|-----------|---------|
| `Sources/Model/SplitMinimap.swift` | Minimap model: tree -> normalized pane rects |
| `Sources/View/MinimapView.swift` | SwiftUI rendering of minimap panes |
| `Tests/SplitMinimapTests.swift` | Red/green tests for minimap layout computation |

### Modified Files

| File Path | Changes |
|-----------|---------|
| `Sources/Model/TabInfo.swift` | Add `minimap: SplitMinimap?` field |
| `Sources/View/TabRow.swift` | Render MinimapView when tab has splits |

## Implementation Details

### SplitMinimap model

```swift
// Sources/Model/SplitMinimap.swift
struct MinimapPane: Equatable {
    let leafID: UUID
    let rect: MinimapRect       // normalized 0-1 coordinates
    let isFocused: Bool
    let colorOverride: TabColor?    // per-pane color (nil = use tab color)
    let claudeCode: ClaudeCodeStatus?  // nil if no Claude Code in this pane
}

struct MinimapRect: Equatable {
    let originX: Double     // 0-1
    let originY: Double     // 0-1
    let width: Double       // 0-1
    let height: Double      // 0-1
}

struct SplitMinimap: Equatable {
    let panes: [MinimapPane]

    /// Compute minimap layout from a split tree.
    static func from(
        node: SplitNode,
        focusedLeafID: UUID?
    ) -> SplitMinimap
}
```

The `from()` method recursively walks the tree, splitting the available rect according to orientation and ratio at each branch. Leaves produce `MinimapPane` entries.

### MinimapView

```swift
// Sources/View/MinimapView.swift
struct MinimapView: View {
    let minimap: SplitMinimap
    let accentColor: Color

    // Renders proportionally within the tab row
    // Each pane is a rounded rect with 1pt gap
    // Unfocused panes: muted/low-alpha fill, no bright border
    // Focused pane: bright colored border (matches the real app's
    //   focus border), muted fill -- only the focused pane gets
    //   the bright edge treatment
    // Single-pane tabs: same treatment as a focused pane
    // Claude Code indicator: small symbol overlaid on the pane
    //   (muted when working, brighter when waiting for response)
}
```

## Red/Green Tests

### SplitMinimapTests.swift

- `singleLeafProducesOnePane` -- single leaf -> one pane at full rect (0,0,1,1)
- `horizontalSplitProducesTwoPanes` -- 50/50 horizontal -> two side-by-side rects
- `verticalSplitProducesTwoPanes` -- 50/50 vertical -> two stacked rects
- `customRatioAffectsLayout` -- 0.3 ratio -> first pane is 30%, second is 70%
- `nestedSplitProducesThreePanes` -- (A | (B / C)) -> three rects
- `focusedPaneIsMarked` -- focused leaf ID matches MinimapPane.isFocused
- `fourPaneGridLayout` -- 2x2 grid -> four quarter-sized rects

## Verification

- `just test` -- all minimap model tests pass (red first, then green)
- `just run` -- create splits, verify minimap appears in tab sidebar
- Minimap updates when splits are created/closed
- Focused pane indicator updates when focus changes
