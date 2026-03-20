# Phase 2: Tab Model and Vertical Sidebar

## Goal

Add the vertical tab sidebar with large font, static positioning, drag-to-reorder, per-tab colors, and prominent directory display. Each tab contains a single terminal surface (splits come in Phase 3).

## Technical Approach

### Tab data model

The core data model is a `Tab` class and a `TabStore` that manages an ordered collection.

```swift
// Sources/Model/Tab.swift
@Observable
final class Tab: Identifiable {
    let id: UUID
    var name: String              // user-assigned name (empty = use autoName)
    var autoName: String          // derived from working directory
    var color: TabColor           // user-assigned or .auto
    var position: Int             // explicit sort order
    var workingDirectory: String? // from ghostty PWD callback
    var surfaceID: UUID           // the ghostty surface in this tab

    var displayName: String {
        name.isEmpty ? autoName : name
    }
}
```

```swift
// Sources/Model/TabColor.swift
enum TabColor: Codable, Equatable {
    case preset(PresetColor)
    case auto

    enum PresetColor: String, Codable, CaseIterable {
        case red, orange, yellow, green, blue, indigo, purple, pink, brown, gray
    }
}
```

`TabColor.auto` means "derive from working directory" (implemented in Phase 5). For Phase 2, `.auto` renders as a neutral/default color.

```swift
// Sources/Model/TabStore.swift
@Observable
final class TabStore {
    private(set) var tabs: [Tab] = []

    // Mutations (all maintain position consistency)
    func append(tab: Tab)             // new tab at bottom
    func close(id: UUID)              // remove tab, reindex positions
    func move(fromIndex: Int, toIndex: Int)  // drag reorder
    func rename(id: UUID, name: String)
    func setColor(id: UUID, color: TabColor)

    var activeTabID: UUID?

    // Derived
    var activeTab: Tab? { tabs.first { $0.id == activeTabID } }
    func tab(at index: Int) -> Tab? { ... }
}
```

**Position invariant:** After every mutation, `tabs[i].position == i` for all `i`. The `tabs` array is always sorted by `position`. This makes the ordering deterministic and testable.

### Sidebar UI

The sidebar is a vertical list on the left side of the window, using a fixed width (resizable later in Phase 5).

```
+------------------+--------------------------------------------+
| [Tab 1 - red   ] |                                            |
| ~/projects/foo   |                                            |
|                  |          Terminal Surface                   |
| [Tab 2 - green ] |          (active tab's terminal)           |
| ~/work/bar       |                                            |
|                  |                                            |
| [Tab 3 - blue  ] |                                            |
| ~/scratch        |                                            |
|                  |                                            |
|                  |                                            |
| [+] New Tab      |                                            |
+------------------+--------------------------------------------+
```

Key visual properties:
- **Tab name**: Large font (16-18pt system font, bold). This is the primary visual element.
- **Directory**: Shown below the name in a smaller font (12-13pt). Last path component by default, full path on hover or when ambiguous.
- **Color indicator**: Vertical bar (4px wide) on the left edge of each tab row, using the tab's assigned color.
- **Active tab**: Background tinted with the tab's color at low opacity. The color indicator bar is fully saturated.
- **Inactive tabs**: Subtle background, muted color indicator.

### Sidebar structure

```
Sources/View/
  MainWindow.swift          -- HSplitView: sidebar | terminal content
  TabSidebar.swift          -- The full sidebar view (list + footer)
  TabRow.swift              -- Single tab row (name, directory, color bar)
  TabContextMenu.swift      -- Right-click menu (rename, set color, close)
  TabColorPicker.swift      -- Color selection submenu/popover
```

`MainWindow.swift` uses an `HSplitView` (or `NavigationSplitView`) with the sidebar on the left and the active tab's terminal surface on the right.

### Tab operations

| Operation | Trigger | Behavior |
|-----------|---------|----------|
| New tab | Cmd+T or "+" button | Create tab at bottom, switch to it |
| Close tab | Cmd+W or context menu | Close surface, remove tab, switch to adjacent |
| Switch tab | Click, Cmd+1-9, Cmd+Shift+[/] | Set activeTabID, show that tab's surface |
| Rename | Double-click name or context menu | Inline text field edit |
| Set color | Context menu > Color | Show preset color picker |
| Reorder | Drag tab row | Move in TabStore, update positions |

### Keyboard shortcuts

- `Cmd+T` -- new tab
- `Cmd+W` -- close active tab
- `Cmd+1` through `Cmd+9` -- switch to tab by position
- `Cmd+Shift+[` / `Cmd+Shift+]` -- previous/next tab

### Integration with Ghostty

When a new tab is created:
1. `TabStore.append()` creates a `Tab` with a new UUID
2. `AppDelegate` creates a new `Ghostty.SurfaceView` via the Ghostty.App's surface creation flow
3. The surface ID is stored in `Tab.surfaceID`
4. `MainWindow` looks up the surface for the active tab and displays it

When Ghostty reports a title change (`GHOSTTY_ACTION_SET_TITLE`) or working directory change (`GHOSTTY_ACTION_PWD`):
1. Find the tab whose `surfaceID` matches the reporting surface
2. Update `tab.autoName` (from title) or `tab.workingDirectory` (from PWD)

## File Changes

### New files
| File | Purpose |
|------|---------|
| `Sources/Model/Tab.swift` | Tab data model |
| `Sources/Model/TabStore.swift` | Ordered tab collection with mutations |
| `Sources/Model/TabColor.swift` | Color assignment types |
| `Sources/View/TabSidebar.swift` | Vertical tab sidebar view |
| `Sources/View/TabRow.swift` | Single tab row view |
| `Sources/View/TabContextMenu.swift` | Right-click context menu |
| `Sources/View/TabColorPicker.swift` | Color picker submenu |
| `Tests/TabTests.swift` | Tab model tests |
| `Tests/TabStoreTests.swift` | TabStore ordering/mutation tests |
| `Tests/TabColorTests.swift` | TabColor equality/coding tests |

### Modified files
| File | Changes |
|------|---------|
| `Sources/App/MainWindow.swift` | HSplitView layout: sidebar + terminal |
| `Sources/App/AppDelegate.swift` | Handle new tab creation, surface lifecycle, title/PWD callbacks |

## Testing

### TabStoreTests.swift

```swift
import Testing
@testable import montty

struct TabStoreTests {
    @Test func newTabAppendsAtBottom() {
        let store = TabStore()
        let tab1 = Tab(name: "first")
        let tab2 = Tab(name: "second")
        store.append(tab: tab1)
        store.append(tab: tab2)

        #expect(store.tabs.count == 2)
        #expect(store.tabs[0].id == tab1.id)
        #expect(store.tabs[1].id == tab2.id)
        #expect(store.tabs[0].position == 0)
        #expect(store.tabs[1].position == 1)
    }

    @Test func closeRemovesAndReindexes() {
        let store = TabStore()
        let a = Tab(name: "a")
        let b = Tab(name: "b")
        let c = Tab(name: "c")
        store.append(tab: a)
        store.append(tab: b)
        store.append(tab: c)

        store.close(id: b.id)

        #expect(store.tabs.count == 2)
        #expect(store.tabs[0].id == a.id)
        #expect(store.tabs[0].position == 0)
        #expect(store.tabs[1].id == c.id)
        #expect(store.tabs[1].position == 1)
    }

    @Test func moveReordersAndReindexes() {
        let store = TabStore()
        let a = Tab(name: "a")
        let b = Tab(name: "b")
        let c = Tab(name: "c")
        store.append(tab: a)
        store.append(tab: b)
        store.append(tab: c)

        store.move(fromIndex: 2, toIndex: 0)

        #expect(store.tabs.map(\.name) == ["c", "a", "b"])
        #expect(store.tabs.map(\.position) == [0, 1, 2])
    }

    @Test func closeLastTabSwitchesToPrevious() {
        let store = TabStore()
        let a = Tab(name: "a")
        let b = Tab(name: "b")
        store.append(tab: a)
        store.append(tab: b)
        store.activeTabID = b.id

        store.close(id: b.id)

        #expect(store.activeTabID == a.id)
    }
}
```

### TabTests.swift

```swift
@Test func displayNamePrefersUserName() {
    let tab = Tab(name: "my project")
    tab.autoName = "some-directory"
    #expect(tab.displayName == "my project")
}

@Test func displayNameFallsBackToAutoName() {
    let tab = Tab(name: "")
    tab.autoName = "workspace"
    #expect(tab.displayName == "workspace")
}
```

### TabColorTests.swift

```swift
@Test func presetColorCodableRoundTrip() throws {
    let color = TabColor.preset(.red)
    let data = try JSONEncoder().encode(color)
    let decoded = try JSONDecoder().decode(TabColor.self, from: data)
    #expect(decoded == color)
}

@Test func autoColorCodableRoundTrip() throws {
    let color = TabColor.auto
    let data = try JSONEncoder().encode(color)
    let decoded = try JSONDecoder().decode(TabColor.self, from: data)
    #expect(decoded == .auto)
}
```

## Verification

1. `just test` -- all tab model tests pass
2. Launch app -- sidebar appears on the left with one tab
3. `Cmd+T` -- new tab appears at bottom of sidebar
4. Click tabs -- switches active terminal
5. Drag a tab -- reorders in sidebar, stays in new position
6. Right-click > Rename -- can edit tab name, large font displays it
7. Right-click > Color > Red -- color bar on left edge turns red, active tab tints red
8. `Cmd+W` -- closes tab, switches to adjacent
9. `Cmd+1` through `Cmd+9` -- switches to tab by position
10. Directory shows below tab name in smaller font
