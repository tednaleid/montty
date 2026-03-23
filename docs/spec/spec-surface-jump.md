# Surface Jump: ace-jump/easy-motion for montty

## Goal

Let users press a key combo to label every surface across all tabs with jump targets. The user types the label key(s) to instantly jump to that surface (switching tabs if needed). Closer/more-accessible surfaces get shorter labels. Clicking a minimap pane also jumps to that surface.

## Trigger

Add a "Jump to Surface" menu item with default shortcut `Cmd+;`. Users can override the shortcut via System Settings > Keyboard > App Shortcuts by matching the menu title. This is the standard macOS pattern for configurable shortcuts.

During jump mode, an NSEvent local monitor captures `a-z` and `Escape` keys for label input.

## Label assignment algorithm

1. Collect all surfaces across all tabs as `(tabID, leafID, surfaceID)` tuples
2. Sort by priority: active tab surfaces first (ordered by tree position), then other tabs by tab position, each tab's surfaces by tree position
3. Assign labels:
   - If n <= 26: all single-char (`a`-`z`)
   - If n > 26: closest `26 - P` get single-char, rest get double-char (`aa`-`az`, `ba`-`bz`, etc.) where `P = min(26, ceil((n - 26) / 25))`
4. Pure function, testable without UI

## State machine

```
Normal --[Cmd+;]--> JumpMode(labels, buffer="")
JumpMode --[a-z, single match]--> Jump to surface, back to Normal
JumpMode --[a-z, prefix match]--> JumpMode(labels, buffer="a") (dim non-matching)
JumpMode --[a-z after prefix, match]--> Jump to surface, back to Normal
JumpMode --[Escape / invalid key]--> Normal
```

State lives as `@Published var jumpState: JumpState?` on AppDelegate (nil = normal mode). When non-nil, views read it to show overlays.

## Rendering

**Badge style** (consistent across surfaces and minimaps):
- Rounded rect background using the tab's color (preset color or accent)
- Bold white text, centered in the badge
- Non-matching labels dim during prefix input

**Active tab surfaces** (SplitContainerView):
- Large badge centered on each surface (prominent, easy to read)
- Same label appears on both the surface and its corresponding minimap pane

**Minimap panes** (MinimapView, all tabs):
- Same rounded-rect badge style, scaled to minimap size
- Labels match the surface badges on the active tab
- Other tabs' minimap panes also get labeled

## Jump action

When a label is matched:
1. Look up target `(tabID, leafID)`
2. If different tab: switch `tabStore.activeTabID`
3. Call `setFocusedLeaf(leafID, in: tab)`
4. Clear `jumpState`

## Key interception during jump mode

While `jumpState` is non-nil, the NSEvent monitor consumes all keyDown events:
- `a-z`: feed to state machine
- `Escape`: cancel
- All other keys: cancel and pass through

## Minimap click-to-jump

Clicking a pane in any tab's minimap jumps to that tab and focuses that surface. This works independently of jump mode (always available).

## Files

### New files
- `Sources/Model/JumpLabels.swift` -- pure label generation algorithm + JumpState type
- `Tests/JumpLabelsTests.swift` -- test label assignment and state machine

### Modified files
- `Sources/App/AppDelegate.swift` -- jumpState property, NSEvent monitor, jump execution, minimap click handler
- `Sources/View/SplitContainerView.swift` -- render jump badges on surfaces
- `Sources/View/MinimapView.swift` -- render jump badges on minimap panes, add tap gesture per pane
- `Sources/View/TabRow.swift` -- pass jumpState and onJumpToSurface callback
- `Sources/View/TabSidebar.swift` -- pass jumpState and onJumpToSurface callback
- `Sources/App/MainWindow.swift` -- wire up jumpState and callback

## Testing

**Unit tests (red/green)**:
- Label generation: 1 surface, 5 surfaces, 26 surfaces, 27 surfaces, 52 surfaces
- Label priority ordering: active tab surfaces get shortest labels
- State machine: key input transitions, prefix buffering, escape cancellation

**Manual verification**:
- `just run` -> Cmd+; -> labels appear on all surfaces and minimaps
- Type a single-char label -> jumps to correct surface
- Type a double-char label -> first char dims non-matching, second char jumps
- Escape cancels
- Cross-tab jump works (switches tab and focuses surface)
- Click minimap pane -> jumps to that tab and surface
