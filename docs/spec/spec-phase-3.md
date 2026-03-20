# Phase 3: Splits

## Goal

Add horizontal and vertical splits within each tab. Each tab contains a binary split tree of terminal surfaces. Dividers are draggable to resize panes. Focus navigates between splits with keyboard shortcuts.

## Technical Approach

### Split tree data model

A tab's content is a binary tree where leaves are terminal surfaces and branches are split containers.

```swift
// Sources/Model/SplitNode.swift
indirect enum SplitNode: Identifiable, Equatable {
    case leaf(SurfaceLeaf)
    case split(SplitBranch)

    var id: UUID {
        switch self {
        case .leaf(let l): l.id
        case .split(let b): b.id
        }
    }
}

struct SurfaceLeaf: Identifiable, Equatable {
    let id: UUID
    var surfaceID: UUID  // maps to a Ghostty.SurfaceView
}

struct SplitBranch: Identifiable, Equatable {
    let id: UUID
    var orientation: SplitOrientation
    var ratio: CGFloat  // 0.0-1.0, divider position
    var first: SplitNode
    var second: SplitNode
}

enum SplitOrientation: String, Codable {
    case horizontal  // left | right
    case vertical    // top / bottom
}
```

### Split operations

All operations are pure functions on the tree, making them testable without any UI:

```swift
// Sources/Model/SplitTree.swift
enum SplitTree {
    /// Split the leaf with the given ID, inserting a new leaf.
    /// Returns the modified tree and the new leaf's ID.
    static func split(
        node: SplitNode,
        leafID: UUID,
        orientation: SplitOrientation,
        newLeafID: UUID,
        newSurfaceID: UUID
    ) -> SplitNode

    /// Remove a leaf by ID, collapsing its parent branch.
    /// Returns nil if the tree becomes empty.
    static func close(
        node: SplitNode,
        leafID: UUID
    ) -> SplitNode?

    /// Find a leaf by its surface ID.
    static func findLeaf(
        node: SplitNode,
        surfaceID: UUID
    ) -> SurfaceLeaf?

    /// Collect all leaf IDs in order (left-to-right, top-to-bottom).
    static func allLeaves(node: SplitNode) -> [SurfaceLeaf]

    /// Navigate focus: given current leaf, find next/previous in tree order.
    static func nextLeaf(node: SplitNode, after leafID: UUID) -> SurfaceLeaf?
    static func previousLeaf(node: SplitNode, before leafID: UUID) -> SurfaceLeaf?
}
```

### Tab model changes

The `Tab` model from Phase 2 changes from holding a single `surfaceID` to holding a `SplitNode` tree:

```swift
@Observable
final class Tab: Identifiable {
    let id: UUID
    var name: String
    var autoName: String
    var color: TabColor
    var position: Int
    var workingDirectory: String?
    var splitRoot: SplitNode           // was: surfaceID
    var focusedLeafID: UUID?           // which leaf has keyboard focus
}
```

### Split container view

A recursive SwiftUI view that renders the split tree:

```swift
// Sources/View/SplitContainerView.swift
struct SplitContainerView: View {
    let node: SplitNode
    let focusedLeafID: UUID?
    let surfaceLookup: (UUID) -> Ghostty.SurfaceView?
    let onFocusLeaf: (UUID) -> Void

    var body: some View {
        switch node {
        case .leaf(let leaf):
            TerminalSurfaceHost(
                surfaceView: surfaceLookup(leaf.surfaceID),
                isFocused: leaf.id == focusedLeafID,
                onTap: { onFocusLeaf(leaf.id) }
            )
        case .split(let branch):
            SplitDividerView(
                orientation: branch.orientation,
                ratio: branch.ratio
            ) {
                SplitContainerView(
                    node: branch.first,
                    focusedLeafID: focusedLeafID,
                    surfaceLookup: surfaceLookup,
                    onFocusLeaf: onFocusLeaf
                )
            } second: {
                SplitContainerView(
                    node: branch.second,
                    focusedLeafID: focusedLeafID,
                    surfaceLookup: surfaceLookup,
                    onFocusLeaf: onFocusLeaf
                )
            }
        }
    }
}
```

### Divider view

The `SplitDividerView` renders two children separated by a draggable divider:

```swift
// Sources/View/SplitDividerView.swift
struct SplitDividerView<First: View, Second: View>: View {
    let orientation: SplitOrientation
    @State var ratio: CGFloat  // bound to branch.ratio
    let first: () -> First
    let second: () -> Second

    // Divider: 6px visual, full-width hit target
    // Drag gesture updates ratio, clamped to [0.1, 0.9]
}
```

### Focus management

When a split has focus:
1. The `focusedLeafID` on the tab is set
2. `ghostty_surface_set_focus(true)` is called on the focused surface
3. `ghostty_surface_set_focus(false)` is called on all other surfaces in the tab
4. A subtle border or highlight indicates the focused pane

Focus navigation:
- Clicking a pane focuses it
- `Cmd+Option+Arrow` moves focus to the adjacent pane in that direction
- `Cmd+Shift+D` splits the focused pane vertically (left/right)
- `Cmd+D` splits the focused pane horizontally (left/right -- matching iTerm2 convention)
- `Cmd+W` when in a split closes the focused pane (not the whole tab)

### Ghostty integration

When a split is requested (either via keyboard shortcut or Ghostty's `GHOSTTY_ACTION_NEW_SPLIT`):
1. `AppDelegate` intercepts the split action
2. Creates a new `Ghostty.SurfaceView`
3. Calls `SplitTree.split()` on the active tab's `splitRoot`
4. Updates the tab's `splitRoot` and `focusedLeafID`
5. SwiftUI re-renders the `SplitContainerView`

When a surface closes:
1. Find the leaf containing that surface
2. Call `SplitTree.close()` to remove it and collapse the parent branch
3. Focus moves to the sibling that absorbed the space
4. If the last leaf is closed, the tab itself closes

## File Changes

### New files
| File | Purpose |
|------|---------|
| `Sources/Model/SplitNode.swift` | SplitNode enum, SurfaceLeaf, SplitBranch types |
| `Sources/Model/SplitTree.swift` | Pure tree operations (split, close, find, navigate) |
| `Sources/View/SplitContainerView.swift` | Recursive split view |
| `Sources/View/SplitDividerView.swift` | Draggable divider between panes |
| `Sources/View/TerminalSurfaceHost.swift` | NSViewRepresentable wrapping SurfaceView |
| `Tests/SplitNodeTests.swift` | SplitNode type tests |
| `Tests/SplitTreeTests.swift` | Tree operation tests |

### Modified files
| File | Changes |
|------|---------|
| `Sources/Model/Tab.swift` | Replace `surfaceID: UUID` with `splitRoot: SplitNode` + `focusedLeafID: UUID?` |
| `Sources/App/MainWindow.swift` | Render `SplitContainerView` for active tab instead of single surface |
| `Sources/App/AppDelegate.swift` | Handle split creation/close, manage surface lifecycle for splits |
| `Tests/TabStoreTests.swift` | Update tab creation to use SplitNode |

## Testing

### SplitTreeTests.swift

```swift
import Testing
@testable import montty

struct SplitTreeTests {
    @Test func splitLeafCreatesHorizontalBranch() {
        let leaf = SurfaceLeaf(id: UUID(), surfaceID: UUID())
        let root = SplitNode.leaf(leaf)
        let newSurfaceID = UUID()
        let newLeafID = UUID()

        let result = SplitTree.split(
            node: root,
            leafID: leaf.id,
            orientation: .horizontal,
            newLeafID: newLeafID,
            newSurfaceID: newSurfaceID
        )

        guard case .split(let branch) = result else {
            Issue.record("Expected split branch")
            return
        }
        #expect(branch.orientation == .horizontal)
        #expect(branch.ratio == 0.5)

        // First child is the original leaf
        guard case .leaf(let first) = branch.first else {
            Issue.record("Expected leaf")
            return
        }
        #expect(first.id == leaf.id)

        // Second child is the new leaf
        guard case .leaf(let second) = branch.second else {
            Issue.record("Expected leaf")
            return
        }
        #expect(second.id == newLeafID)
        #expect(second.surfaceID == newSurfaceID)
    }

    @Test func closeLeafCollapsesParent() {
        let leaf1 = SurfaceLeaf(id: UUID(), surfaceID: UUID())
        let leaf2 = SurfaceLeaf(id: UUID(), surfaceID: UUID())
        let branch = SplitBranch(
            id: UUID(),
            orientation: .horizontal,
            ratio: 0.5,
            first: .leaf(leaf1),
            second: .leaf(leaf2)
        )
        let root = SplitNode.split(branch)

        let result = SplitTree.close(node: root, leafID: leaf2.id)

        // Should collapse to just leaf1
        guard case .leaf(let remaining) = result else {
            Issue.record("Expected single leaf after close")
            return
        }
        #expect(remaining.id == leaf1.id)
    }

    @Test func closeLastLeafReturnsNil() {
        let leaf = SurfaceLeaf(id: UUID(), surfaceID: UUID())
        let root = SplitNode.leaf(leaf)

        let result = SplitTree.close(node: root, leafID: leaf.id)
        #expect(result == nil)
    }

    @Test func allLeavesReturnsInOrder() {
        // Build: (leaf1 | (leaf2 / leaf3))
        let leaf1 = SurfaceLeaf(id: UUID(), surfaceID: UUID())
        let leaf2 = SurfaceLeaf(id: UUID(), surfaceID: UUID())
        let leaf3 = SurfaceLeaf(id: UUID(), surfaceID: UUID())

        let innerBranch = SplitBranch(
            id: UUID(), orientation: .vertical, ratio: 0.5,
            first: .leaf(leaf2), second: .leaf(leaf3)
        )
        let root = SplitNode.split(SplitBranch(
            id: UUID(), orientation: .horizontal, ratio: 0.5,
            first: .leaf(leaf1), second: .split(innerBranch)
        ))

        let leaves = SplitTree.allLeaves(node: root)
        #expect(leaves.map(\.id) == [leaf1.id, leaf2.id, leaf3.id])
    }

    @Test func nextLeafWrapsAround() {
        let leaf1 = SurfaceLeaf(id: UUID(), surfaceID: UUID())
        let leaf2 = SurfaceLeaf(id: UUID(), surfaceID: UUID())
        let root = SplitNode.split(SplitBranch(
            id: UUID(), orientation: .horizontal, ratio: 0.5,
            first: .leaf(leaf1), second: .leaf(leaf2)
        ))

        let next = SplitTree.nextLeaf(node: root, after: leaf2.id)
        #expect(next?.id == leaf1.id)
    }

    @Test func splitDeepNestedLeaf() {
        // Build a 3-level tree, split the deepest leaf
        let leaf1 = SurfaceLeaf(id: UUID(), surfaceID: UUID())
        let leaf2 = SurfaceLeaf(id: UUID(), surfaceID: UUID())
        let leaf3 = SurfaceLeaf(id: UUID(), surfaceID: UUID())

        let inner = SplitBranch(
            id: UUID(), orientation: .vertical, ratio: 0.5,
            first: .leaf(leaf2), second: .leaf(leaf3)
        )
        let root = SplitNode.split(SplitBranch(
            id: UUID(), orientation: .horizontal, ratio: 0.5,
            first: .leaf(leaf1), second: .split(inner)
        ))

        let newLeafID = UUID()
        let result = SplitTree.split(
            node: root,
            leafID: leaf3.id,
            orientation: .horizontal,
            newLeafID: newLeafID,
            newSurfaceID: UUID()
        )

        let allLeaves = SplitTree.allLeaves(node: result)
        #expect(allLeaves.count == 4)
        #expect(allLeaves.map(\.id).contains(newLeafID))
    }
}
```

## Verification

1. `just test` -- all split tree tests pass
2. Launch app -- single pane per tab (unchanged from Phase 2)
3. `Cmd+D` -- splits current pane vertically (side by side)
4. `Cmd+Shift+D` -- splits current pane horizontally (stacked)
5. Type in each pane independently -- both terminals work
6. Drag divider -- panes resize proportionally
7. `Cmd+Option+Left/Right` -- focus moves between horizontal splits
8. `Cmd+W` in a split -- closes focused pane, sibling expands
9. Close all splits in a tab -- tab still exists with one pane
10. Create splits in one tab, switch to another tab, switch back -- split layout preserved
