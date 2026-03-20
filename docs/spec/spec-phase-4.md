# Phase 4: Session Persistence

## Goal

Save the full app state (tabs, splits, names, colors, positions, window frame) to a JSON file. Auto-save periodically. Restore everything on launch so the user never loses their workspace layout.

## Technical Approach

### Snapshot types

All types are `Codable` with a version field for future migration.

```swift
// Sources/Persistence/SessionSnapshot.swift
struct SessionSnapshot: Codable {
    static let currentVersion = 1

    var version: Int = Self.currentVersion
    var windowFrame: CGRect
    var sidebarWidth: CGFloat
    var activeTabID: UUID?
    var tabs: [TabSnapshot]
}

struct TabSnapshot: Codable {
    var id: UUID
    var name: String
    var color: TabColor
    var position: Int
    var workingDirectory: String?
    var focusedLeafID: UUID?
    var splitLayout: SplitNodeSnapshot
}

indirect enum SplitNodeSnapshot: Codable {
    case leaf(LeafSnapshot)
    case split(SplitBranchSnapshot)
}

struct LeafSnapshot: Codable {
    var id: UUID
    var workingDirectory: String?
}

struct SplitBranchSnapshot: Codable {
    var id: UUID
    var orientation: SplitOrientation
    var ratio: CGFloat
    var first: SplitNodeSnapshot
    var second: SplitNodeSnapshot
}
```

### Session store

```swift
// Sources/Persistence/SessionStore.swift
@Observable
final class SessionStore {
    private let fileURL: URL  // ~/Library/Application Support/montty/session.json
    private var autoSaveTimer: Timer?

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("montty")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        fileURL = appSupport.appendingPathComponent("session.json")
    }

    func save(snapshot: SessionSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    func load() throws -> SessionSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(SessionSnapshot.self, from: data)
    }

    func startAutoSave(interval: TimeInterval = 8.0, snapshotProvider: @escaping () -> SessionSnapshot) {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            let snapshot = snapshotProvider()
            try? self?.save(snapshot: snapshot)
        }
    }

    func stopAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }
}
```

### Snapshot creation

The `AppDelegate` (or a coordinator) creates snapshots from live state:

```swift
extension AppDelegate {
    func createSnapshot() -> SessionSnapshot {
        SessionSnapshot(
            windowFrame: window.frame,
            sidebarWidth: sidebarWidth,
            activeTabID: tabStore.activeTabID,
            tabs: tabStore.tabs.map { tab in
                TabSnapshot(
                    id: tab.id,
                    name: tab.name,
                    color: tab.color,
                    position: tab.position,
                    workingDirectory: tab.workingDirectory,
                    focusedLeafID: tab.focusedLeafID,
                    splitLayout: snapshotSplitNode(tab.splitRoot)
                )
            }
        )
    }

    private func snapshotSplitNode(_ node: SplitNode) -> SplitNodeSnapshot {
        switch node {
        case .leaf(let leaf):
            // Look up working directory from the surface
            let dir = surfaceLookup(leaf.surfaceID)?.pwd
            return .leaf(LeafSnapshot(id: leaf.id, workingDirectory: dir))
        case .split(let branch):
            return .split(SplitBranchSnapshot(
                id: branch.id,
                orientation: branch.orientation,
                ratio: branch.ratio,
                first: snapshotSplitNode(branch.first),
                second: snapshotSplitNode(branch.second)
            ))
        }
    }
}
```

### Restoration

On launch, if a session file exists:
1. Decode `SessionSnapshot`
2. Set window frame and sidebar width
3. For each `TabSnapshot`:
   a. Create a `Tab` with the saved id, name, color, position
   b. Walk the `SplitNodeSnapshot` tree
   c. For each leaf, create a new `Ghostty.SurfaceView` with `working_directory` set to the saved directory
   d. Build the live `SplitNode` tree
4. Set `activeTabID`
5. Focus the saved `focusedLeafID` in the active tab

If restoration fails (corrupt file, etc.), fall back to creating a single empty tab.

### Save triggers

- **Auto-save timer**: every 8 seconds
- **App termination**: `applicationWillTerminate` saves final snapshot
- **Tab mutation**: after create/close/reorder (debounced, not immediate)

## File Changes

### New files
| File | Purpose |
|------|---------|
| `Sources/Persistence/SessionSnapshot.swift` | Codable snapshot types |
| `Sources/Persistence/SessionStore.swift` | File I/O, auto-save timer |
| `Tests/SessionSnapshotTests.swift` | Round-trip encode/decode tests |
| `Tests/SessionStoreTests.swift` | File save/load tests |

### Modified files
| File | Changes |
|------|---------|
| `Sources/App/AppDelegate.swift` | Create snapshots from live state, restore on launch, start auto-save |
| `Sources/App/MainWindow.swift` | Expose window frame and sidebar width for snapshotting |

## Testing

### SessionSnapshotTests.swift

```swift
import Testing
import Foundation
@testable import montty

struct SessionSnapshotTests {
    @Test func roundTripSimpleSession() throws {
        let leafSnap = LeafSnapshot(id: UUID(), workingDirectory: "/Users/ted/projects")
        let tabSnap = TabSnapshot(
            id: UUID(),
            name: "my project",
            color: .preset(.red),
            position: 0,
            workingDirectory: "/Users/ted/projects",
            focusedLeafID: leafSnap.id,
            splitLayout: .leaf(leafSnap)
        )
        let snapshot = SessionSnapshot(
            windowFrame: CGRect(x: 100, y: 100, width: 1200, height: 800),
            sidebarWidth: 220,
            activeTabID: tabSnap.id,
            tabs: [tabSnap]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)

        #expect(decoded.version == 1)
        #expect(decoded.tabs.count == 1)
        #expect(decoded.tabs[0].name == "my project")
        #expect(decoded.tabs[0].color == .preset(.red))
        #expect(decoded.activeTabID == tabSnap.id)
        #expect(decoded.sidebarWidth == 220)
    }

    @Test func roundTripSplitLayout() throws {
        let leaf1 = LeafSnapshot(id: UUID(), workingDirectory: "/tmp/a")
        let leaf2 = LeafSnapshot(id: UUID(), workingDirectory: "/tmp/b")
        let splitSnap = SplitBranchSnapshot(
            id: UUID(),
            orientation: .horizontal,
            ratio: 0.6,
            first: .leaf(leaf1),
            second: .leaf(leaf2)
        )
        let tabSnap = TabSnapshot(
            id: UUID(),
            name: "",
            color: .auto,
            position: 0,
            workingDirectory: nil,
            focusedLeafID: leaf1.id,
            splitLayout: .split(splitSnap)
        )
        let snapshot = SessionSnapshot(
            windowFrame: .zero,
            sidebarWidth: 200,
            activeTabID: tabSnap.id,
            tabs: [tabSnap]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)

        guard case .split(let branch) = decoded.tabs[0].splitLayout else {
            Issue.record("Expected split layout")
            return
        }
        #expect(branch.orientation == .horizontal)
        #expect(branch.ratio == 0.6)
    }

    @Test func roundTripMultipleTabs() throws {
        let tabs = (0..<5).map { i in
            TabSnapshot(
                id: UUID(),
                name: "tab \(i)",
                color: .preset(TabColor.PresetColor.allCases[i % TabColor.PresetColor.allCases.count]),
                position: i,
                workingDirectory: "/tmp/\(i)",
                focusedLeafID: UUID(),
                splitLayout: .leaf(LeafSnapshot(id: UUID(), workingDirectory: "/tmp/\(i)"))
            )
        }
        let snapshot = SessionSnapshot(
            windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            sidebarWidth: 250,
            activeTabID: tabs[2].id,
            tabs: tabs
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)

        #expect(decoded.tabs.count == 5)
        #expect(decoded.tabs.map(\.position) == [0, 1, 2, 3, 4])
        #expect(decoded.activeTabID == tabs[2].id)
    }

    @Test func decodesVersion1Explicitly() throws {
        let json = Data("""
        {
            "version": 1,
            "windowFrame": [[0,0],[800,600]],
            "sidebarWidth": 200,
            "tabs": []
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: json)
        #expect(decoded.version == 1)
        #expect(decoded.tabs.isEmpty)
    }
}
```

### SessionStoreTests.swift

```swift
import Testing
import Foundation
@testable import montty

struct SessionStoreTests {
    @Test func saveAndLoadRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SessionStore(directory: tempDir)

        let snapshot = SessionSnapshot(
            windowFrame: CGRect(x: 50, y: 50, width: 1000, height: 700),
            sidebarWidth: 230,
            activeTabID: nil,
            tabs: []
        )

        try store.save(snapshot: snapshot)
        let loaded = try store.load()

        #expect(loaded != nil)
        #expect(loaded?.sidebarWidth == 230)
        #expect(loaded?.windowFrame.width == 1000)
    }

    @Test func loadFromEmptyDirectoryReturnsNil() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SessionStore(directory: tempDir)
        let result = try store.load()
        #expect(result == nil)
    }
}
```

## Verification

1. `just test` -- all snapshot round-trip tests pass
2. Launch app, create 3 tabs with names and colors, split one tab
3. Quit app
4. Check `~/Library/Application Support/montty/session.json` exists and is valid JSON
5. Relaunch app -- all 3 tabs restored with correct names, colors, positions
6. The split layout in the split tab is restored
7. Active tab and focused pane are restored
8. Window position and sidebar width are restored
9. Delete session.json, launch app -- starts with single empty tab (graceful fallback)
