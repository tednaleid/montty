# montty Multi-Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cmd-N opens a montty window that owns its own tabs and splits, and the set of open windows survives a quit while a window closed by hand stays closed.

**Architecture:** Per-window state splits into a pure `WindowModel` (id, `TabStore`, sidebar width) held by a pure `WindowRegistry`, plus a `WindowController` that owns the `NSWindow`. `AppDelegate` keeps app-wide state and routes surface lookups through the registry. Session schema version 4 carries an array of windows, so a closed window is absent from the next save.

**Tech Stack:** Swift 5, AppKit, SwiftUI, Swift Observation (`@Observable`), GhosttyKit, Swift Testing, xcodegen, just.

## Global Constraints

- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`). Never XCTest.
- Red/green: write the failing test first, run it, confirm it fails for the intended reason, then make it pass.
- Tests verify observable runtime behavior, never source text or file contents.
- Model tests must not import AppKit or SwiftUI. Keep logic in `Sources/Model` so it stays testable.
- `just test` does NOT run xcodegen. After creating any new source or test file, run `just generate` or the file is invisible to the build and tests fail with "cannot find X in scope".
- Every new file starts with two `// ABOUTME: ` comment lines.
- Comments and documentation are evergreen: no dates, no ticket IDs, no "currently", no "for now", no narration of what changed or what was tried.
- Documentation contains no emoji, no em-dashes, and no hyperbole.
- `Sources/Ghostty/` is vendored upstream. Do not modify it. Any unavoidable change is marked `// MONTTY:`.
- Ghostty's C API must be called on the main actor.
- Run `just check` and confirm it is green before every commit. Never run `just stop`; it kills by process name and would terminate the montty hosting your shell.
- Session schema version 4 makes a clean break. A v4 file has no top-level `tabs` key.
- Every new `Codable` field decodes with `decodeIfPresent`, `windows` included. Swift's synthesized decoder ignores default values and emits `decode`, which is what broke v2 files during the v3 migration.
- Pane color precedence is unchanged: surface, tab, repo, git signature, gray.
- Non-goals: tabs never move between windows, and there is no `montty window` CLI scope or fourth precedence level.

---

## File Structure

**Create:**
- `Sources/Model/WindowModel.swift` - one window's model state: stable id, `TabStore`, sidebar width.
- `Sources/Model/WindowRegistry.swift` - ordered `WindowModel` list, key window id, add/remove, surface routing.
- `Sources/Model/WindowFrame.swift` - persisted frame value and the clamp that keeps a restored window on screen.
- `Sources/App/WindowController.swift` - owns one `NSWindow` and its `WindowModel`, is its own `NSWindowDelegate`.
- `Tests/WindowRegistryTests.swift`, `Tests/WindowFrameTests.swift`, `Tests/SessionSnapshotV4Tests.swift`.

**Modify:**
- `Sources/Persistence/SessionSnapshot.swift` - v4 schema plus `WindowSnapshot`, with a decoder that reads v3 and v4.
- `Sources/App/AppDelegate.swift` - drop `window` and `tabStore`, gain the registry and routing.
- `Sources/App/AppDelegate+Session.swift` - snapshot and restore across windows.
- `Sources/App/AppDelegate+Focus.swift`, `Sources/App/AppDelegate+GhosttyActions.swift` - route through the key window.
- `Sources/App/MainWindow.swift`, `Sources/View/TabSidebar.swift`, `Sources/View/TabRow.swift` - take per-window state.
- `Sources/App/HookServer.swift`, `Sources/App/DebugServerHandlers.swift` - registry lookups, window identity in `/surfaces`.
- `Sources/App/MenuBuilder.swift` - New Window item, key-window targeting.
- `justfile` - `inspect-screenshot` raises the owning window; add `inspect-windows`.
- `docs/debug-server.md`, `README.md`, `CLAUDE.md`.

---

### Task 1: WindowFrame and its on-screen clamp

**Files:**
- Create: `Sources/Model/WindowFrame.swift`
- Create: `Tests/WindowFrameTests.swift`

**Interfaces:**
- Produces: `struct WindowFrame: Codable, Equatable { var x, y, width, height: Double }`, `WindowFrame.isEmpty`, and `func clamped(toVisible frames: [CGRect]) -> WindowFrame`.

- [ ] **Step 1: Write the failing test**

Create `Tests/WindowFrameTests.swift`:

```swift
// ABOUTME: Verifies a restored window frame lands on a screen that exists,
// ABOUTME: and that a frame already on screen is left alone.

import CoreGraphics
import Testing

@Suite struct WindowFrameTests {
    private let mainScreen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test func leavesAFrameThatIsAlreadyOnScreenAlone() {
        let frame = WindowFrame(x: 100, y: 100, width: 1200, height: 800)

        #expect(frame.clamped(toVisible: [mainScreen]) == frame)
    }

    @Test func pullsAFrameFromADisconnectedDisplayBackOnScreen() {
        let frame = WindowFrame(x: 3000, y: 200, width: 1200, height: 800)

        let clamped = frame.clamped(toVisible: [mainScreen])

        #expect(clamped.x >= mainScreen.minX)
        #expect(clamped.x + clamped.width <= mainScreen.maxX)
        #expect(clamped.width == 1200)
        #expect(clamped.height == 800)
    }

    @Test func shrinksAFrameLargerThanEveryScreen() {
        let frame = WindowFrame(x: 0, y: 0, width: 4000, height: 3000)

        let clamped = frame.clamped(toVisible: [mainScreen])

        #expect(clamped.width <= mainScreen.width)
        #expect(clamped.height <= mainScreen.height)
    }

    @Test func keepsAFrameOnTheScreenItOverlapsMost() {
        let secondScreen = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let frame = WindowFrame(x: 2000, y: 100, width: 800, height: 600)

        #expect(frame.clamped(toVisible: [mainScreen, secondScreen]) == frame)
    }

    @Test func treatsAZeroSizedFrameAsEmpty() {
        #expect(WindowFrame(x: 0, y: 0, width: 0, height: 0).isEmpty)
        #expect(!WindowFrame(x: 0, y: 0, width: 10, height: 10).isEmpty)
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
just generate && just test 2>&1 | grep -E "WindowFrameTests|cannot find"
```

Expected: FAIL with "cannot find 'WindowFrame' in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/Model/WindowFrame.swift`:

```swift
// ABOUTME: A window's saved position and size, and the clamp that keeps a
// ABOUTME: restored window on a display that is actually attached.

import CoreGraphics
import Foundation

struct WindowFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    /// A window that was never laid out has nothing worth restoring.
    var isEmpty: Bool { width <= 0 || height <= 0 }

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x, y: rect.origin.y,
            width: rect.width, height: rect.height
        )
    }

    /// Moves the frame onto the visible screen it overlaps most, or onto the
    /// first screen when it overlaps none. A display that was attached when the
    /// session was saved may be gone by the time it is restored, and a window
    /// placed on it would open where nobody can reach it.
    func clamped(toVisible frames: [CGRect]) -> WindowFrame {
        guard let target = frames.max(by: {
            $0.intersection(rect).area < $1.intersection(rect).area
        }) ?? frames.first else { return self }

        if target.intersection(rect).area > 0, target.contains(rect) { return self }

        let width = min(self.width, target.width)
        let height = min(self.height, target.height)
        let x = min(max(self.x, target.minX), target.maxX - width)
        let y = min(max(self.y, target.minY), target.maxY - height)
        return WindowFrame(x: x, y: y, width: width, height: height)
    }
}

private extension CGRect {
    var area: Double { isNull ? 0 : width * height }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

```bash
just check
```

Expected: all tests pass, zero SwiftLint violations.

- [ ] **Step 5: Commit**

```bash
git add Sources/Model/WindowFrame.swift Tests/WindowFrameTests.swift
git commit -m "feat: keep a restored window frame on an attached display"
```

---

### Task 2: WindowModel and WindowRegistry

**Files:**
- Create: `Sources/Model/WindowModel.swift`
- Create: `Sources/Model/WindowRegistry.swift`
- Create: `Tests/WindowRegistryTests.swift`

**Interfaces:**
- Consumes: `WindowFrame` from Task 1, plus the existing `TabStore` and `Tab`.
- Produces: `WindowModel` with `let id: UUID`, `let tabStore: TabStore`, `var sidebarWidth: Double`, `var frame: WindowFrame`. `WindowRegistry` with `windows: [WindowModel]`, `keyWindowID: UUID?`, `keyWindow: WindowModel?`, `func add(_:) -> WindowModel`, `func remove(id:)`, `func window(id:) -> WindowModel?`, and `func locate(surfaceID: UUID) -> (window: WindowModel, tab: Tab)?`.

- [ ] **Step 1: Write the failing test**

Create `Tests/WindowRegistryTests.swift`:

```swift
// ABOUTME: Verifies the registry tracks windows in order, routes a surface to
// ABOUTME: the window and tab that own it, and keeps a key window that exists.

import Foundation
import Testing

@Suite struct WindowRegistryTests {
    private func tabHolding(_ surfaceID: UUID) -> Tab {
        let tab = Tab(id: UUID(), name: "", position: 0)
        tab.splitRoot = .leaf(SurfaceLeaf(id: UUID(), surfaceID: surfaceID))
        return tab
    }

    @Test func addsWindowsInOrderAndMakesTheFirstOneKey() {
        let registry = WindowRegistry()

        let first = registry.add()
        let second = registry.add()

        #expect(registry.windows.map(\.id) == [first.id, second.id])
        #expect(registry.keyWindowID == first.id)
    }

    @Test func routesASurfaceToTheWindowAndTabThatOwnIt() {
        let registry = WindowRegistry()
        registry.add()
        let second = registry.add()
        let surfaceID = UUID()
        let tab = tabHolding(surfaceID)
        second.tabStore.append(tab: tab)

        let found = registry.locate(surfaceID: surfaceID)

        #expect(found?.window.id == second.id)
        #expect(found?.tab.id == tab.id)
    }

    @Test func routesNothingForASurfaceNoWindowOwns() {
        let registry = WindowRegistry()
        registry.add()

        #expect(registry.locate(surfaceID: UUID()) == nil)
    }

    @Test func removingAWindowDropsItAndItsSurfaces() {
        let registry = WindowRegistry()
        let only = registry.add()
        let surfaceID = UUID()
        only.tabStore.append(tab: tabHolding(surfaceID))

        registry.remove(id: only.id)

        #expect(registry.windows.isEmpty)
        #expect(registry.locate(surfaceID: surfaceID) == nil)
        #expect(registry.keyWindowID == nil)
    }

    @Test func movesTheKeyPointerWhenTheKeyWindowGoesAway() {
        let registry = WindowRegistry()
        let first = registry.add()
        let second = registry.add()
        registry.keyWindowID = second.id

        registry.remove(id: second.id)

        #expect(registry.keyWindowID == first.id)
        #expect(registry.keyWindow?.id == first.id)
    }

    @Test func leavesTheKeyPointerAloneWhenAnotherWindowCloses() {
        let registry = WindowRegistry()
        let first = registry.add()
        let second = registry.add()
        registry.keyWindowID = second.id

        registry.remove(id: first.id)

        #expect(registry.keyWindowID == second.id)
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
just generate && just test 2>&1 | grep -E "WindowRegistryTests|cannot find"
```

Expected: FAIL with "cannot find 'WindowRegistry' in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/Model/WindowModel.swift`:

```swift
// ABOUTME: One window's model state, holding the tabs it owns and the chrome
// ABOUTME: settings that belong to it rather than to the application.

import Foundation

@Observable
final class WindowModel: Identifiable {
    let id: UUID
    let tabStore: TabStore
    /// Each window carries its own sidebar, so its width belongs here.
    var sidebarWidth: Double
    var frame: WindowFrame

    init(
        id: UUID = UUID(),
        tabStore: TabStore = TabStore(),
        sidebarWidth: Double = 200,
        frame: WindowFrame = WindowFrame(x: 0, y: 0, width: 0, height: 0)
    ) {
        self.id = id
        self.tabStore = tabStore
        self.sidebarWidth = sidebarWidth
        self.frame = frame
    }
}
```

Create `Sources/Model/WindowRegistry.swift`:

```swift
// ABOUTME: Every open window in order, and the lookup that answers which window
// ABOUTME: and tab own a given surface.

import Foundation

@Observable
final class WindowRegistry {
    private(set) var windows: [WindowModel] = []

    /// The window holding focus. Subsystems that act on "the current window"
    /// read this rather than assuming there is only one.
    var keyWindowID: UUID?

    var keyWindow: WindowModel? {
        windows.first { $0.id == keyWindowID } ?? windows.first
    }

    @discardableResult
    func add(_ window: WindowModel = WindowModel()) -> WindowModel {
        windows.append(window)
        if keyWindowID == nil { keyWindowID = window.id }
        return window
    }

    func remove(id: UUID) {
        windows.removeAll { $0.id == id }
        guard keyWindowID == id else { return }
        keyWindowID = windows.first?.id
    }

    func window(id: UUID) -> WindowModel? {
        windows.first { $0.id == id }
    }

    /// A surface belongs to exactly one tab in exactly one window. Callers that
    /// hold only a `MONTTY_SURFACE_ID` use this to find both.
    func locate(surfaceID: UUID) -> (window: WindowModel, tab: Tab)? {
        for window in windows {
            if let tab = window.tabStore.tab(forSurfaceID: surfaceID) {
                return (window, tab)
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

```bash
just check
```

Expected: all tests pass, zero SwiftLint violations.

- [ ] **Step 5: Commit**

```bash
git add Sources/Model/WindowModel.swift Sources/Model/WindowRegistry.swift Tests/WindowRegistryTests.swift
git commit -m "feat: track open windows and route surfaces to their owner"
```

---

### Task 3: Session schema version 4

**Files:**
- Modify: `Sources/Persistence/SessionSnapshot.swift`
- Modify: `Sources/App/AppDelegate+Session.swift:8-43` (`createSnapshot`) and `:45-95` (`restoreSession`)
- Create: `Tests/SessionSnapshotV4Tests.swift`

**Interfaces:**
- Consumes: `WindowFrame` from Task 1.
- Produces: `SessionSnapshot.currentVersion == 4`, `SessionSnapshot.windows: [WindowSnapshot]`, `SessionSnapshot.keyWindowID: UUID?`, and `WindowSnapshot(windowID:frame:sidebarWidth:activeTabID:tabs:)`.

This task keeps montty single-window. It changes only the file format and the two functions that read and write it, so the app still builds and runs while the schema moves.

- [ ] **Step 1: Write the failing test**

Create `Tests/SessionSnapshotV4Tests.swift`:

```swift
// ABOUTME: Verifies version 4 sessions round trip, that a version 3 file
// ABOUTME: upgrades into one window, and that a newer file degrades to nothing.

import Foundation
import Testing

@Suite struct SessionSnapshotV4Tests {
    private func decode(_ json: String) throws -> SessionSnapshot {
        try JSONDecoder().decode(SessionSnapshot.self, from: Data(json.utf8))
    }

    @Test func roundTripsSeveralWindows() throws {
        let snapshot = SessionSnapshot(
            surfaceTintEnabled: true,
            windows: [
                WindowSnapshot(
                    windowID: UUID(), frame: WindowFrame(x: 0, y: 0, width: 1200, height: 800),
                    sidebarWidth: 200, activeTabID: nil, tabs: []
                ),
                WindowSnapshot(
                    windowID: UUID(), frame: WindowFrame(x: 50, y: 50, width: 900, height: 600),
                    sidebarWidth: 260, activeTabID: nil, tabs: []
                )
            ],
            repoColorOverrides: [:]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)

        #expect(decoded.version == 4)
        #expect(decoded.windows.count == 2)
        #expect(decoded.windows[1].sidebarWidth == 260)
        #expect(decoded.windows[0].frame.width == 1200)
    }

    @Test func upgradesAVersionThreeFileIntoASingleWindow() throws {
        let tabID = UUID()
        let leafID = UUID()
        let surfaceID = UUID()
        let json = """
        {
          "version": 3,
          "windowX": 12, "windowY": 34, "windowWidth": 1400, "windowHeight": 900,
          "sidebarWidth": 240,
          "surfaceTintEnabled": true,
          "activeTabID": "\(tabID.uuidString)",
          "repoColorOverrides": {},
          "tabs": [
            {
              "tabID": "\(tabID.uuidString)",
              "name": "work",
              "position": 0,
              "focusedLeafID": "\(leafID.uuidString)",
              "splitLayout": {
                "leaf": {
                  "_0": {
                    "id": "\(leafID.uuidString)",
                    "surfaceID": "\(surfaceID.uuidString)"
                  }
                }
              },
              "leafDirectories": ["\(leafID.uuidString)", "/tmp"]
            }
          ]
        }
        """

        let snapshot = try decode(json)

        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows[0].tabs.count == 1)
        #expect(snapshot.windows[0].tabs[0].name == "work")
        #expect(snapshot.windows[0].sidebarWidth == 240)
        #expect(snapshot.windows[0].frame == WindowFrame(x: 12, y: 34, width: 1400, height: 900))
        #expect(snapshot.windows[0].activeTabID == tabID)
        #expect(snapshot.keyWindowID == snapshot.windows[0].windowID)
    }

    @Test func decodesAFileWithNoWindowsKeyAsNoWindows() throws {
        let snapshot = try decode(#"{"version": 4, "surfaceTintEnabled": true}"#)

        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.version == 4)
    }

    @Test func decodesAVersionFiveFileWithoutThrowing() throws {
        let snapshot = try decode(#"{"version": 5, "somethingNew": {"a": 1}}"#)

        #expect(snapshot.version == 5)
        #expect(snapshot.windows.isEmpty)
    }

    @Test func writesNoTopLevelTabsKey() throws {
        let snapshot = SessionSnapshot(
            surfaceTintEnabled: true,
            windows: [WindowSnapshot(
                windowID: UUID(), frame: WindowFrame(x: 0, y: 0, width: 800, height: 600),
                sidebarWidth: 200, activeTabID: nil, tabs: []
            )],
            repoColorOverrides: [:]
        )

        let json = String(bytes: try JSONEncoder().encode(snapshot), encoding: .utf8) ?? ""
        let root = try JSONSerialization.jsonObject(
            with: Data(json.utf8)
        ) as? [String: Any]

        #expect(root?["tabs"] == nil)
        #expect(root?["windows"] != nil)
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
just generate && just test 2>&1 | grep -E "SessionSnapshotV4Tests|cannot find"
```

Expected: FAIL with "cannot find 'WindowSnapshot' in scope".

- [ ] **Step 3: Replace the snapshot types**

In `Sources/Persistence/SessionSnapshot.swift`, replace the whole `SessionSnapshot` struct (keep `TabSnapshot` and its extension exactly as they are) with:

```swift
struct SessionSnapshot: Codable {
    static let currentVersion = 4

    var version: Int = Self.currentVersion
    var surfaceTintEnabled: Bool = true
    var windows: [WindowSnapshot] = []
    var keyWindowID: UUID?
    var repoColorOverrides: [String: PaneTint] = [:]

    init(
        surfaceTintEnabled: Bool = true,
        windows: [WindowSnapshot] = [],
        keyWindowID: UUID? = nil,
        repoColorOverrides: [String: PaneTint] = [:]
    ) {
        self.surfaceTintEnabled = surfaceTintEnabled
        self.windows = windows
        self.keyWindowID = keyWindowID
        self.repoColorOverrides = repoColorOverrides
    }

    /// Reads both shapes. A file with a `windows` array is version 4. A file
    /// without one carries a single window in flat top-level keys, and becomes
    /// one window here. Every key is optional so a file from a later version
    /// decodes to an empty session rather than throwing, which would send it to
    /// quarantine as though it were corrupt.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
            ?? Self.currentVersion
        surfaceTintEnabled = try container.decodeIfPresent(
            Bool.self, forKey: .surfaceTintEnabled) ?? true
        repoColorOverrides = try container.decodeIfPresent(
            [String: PaneTint].self, forKey: .repoColorOverrides) ?? [:]

        if let windows = try container.decodeIfPresent(
            [WindowSnapshot].self, forKey: .windows
        ) {
            self.windows = windows
            keyWindowID = try container.decodeIfPresent(UUID.self, forKey: .keyWindowID)
            return
        }

        let legacy = try LegacyWindow(from: decoder)
        windows = legacy.tabs.isEmpty ? [] : [legacy.asWindowSnapshot()]
        keyWindowID = windows.first?.windowID
    }
}

struct WindowSnapshot: Codable {
    var windowID: UUID
    var frame: WindowFrame
    var sidebarWidth: Double
    var activeTabID: UUID?
    var tabs: [TabSnapshot]
}

extension WindowSnapshot {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowID = try container.decodeIfPresent(UUID.self, forKey: .windowID) ?? UUID()
        frame = try container.decodeIfPresent(WindowFrame.self, forKey: .frame)
            ?? WindowFrame(x: 0, y: 0, width: 0, height: 0)
        sidebarWidth = try container.decodeIfPresent(
            Double.self, forKey: .sidebarWidth) ?? 200
        activeTabID = try container.decodeIfPresent(UUID.self, forKey: .activeTabID)
        tabs = try container.decodeIfPresent([TabSnapshot].self, forKey: .tabs) ?? []
    }
}

/// The single window a session before version 4 stored in flat top-level keys.
private struct LegacyWindow: Decodable {
    var windowX: Double = 0
    var windowY: Double = 0
    var windowWidth: Double = 0
    var windowHeight: Double = 0
    var sidebarWidth: Double = 200
    var activeTabID: UUID?
    var tabs: [TabSnapshot] = []

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowX = try container.decodeIfPresent(Double.self, forKey: .windowX) ?? 0
        windowY = try container.decodeIfPresent(Double.self, forKey: .windowY) ?? 0
        windowWidth = try container.decodeIfPresent(Double.self, forKey: .windowWidth) ?? 0
        windowHeight = try container.decodeIfPresent(Double.self, forKey: .windowHeight) ?? 0
        sidebarWidth = try container.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? 200
        activeTabID = try container.decodeIfPresent(UUID.self, forKey: .activeTabID)
        tabs = try container.decodeIfPresent([TabSnapshot].self, forKey: .tabs) ?? []
    }

    func asWindowSnapshot() -> WindowSnapshot {
        WindowSnapshot(
            windowID: UUID(),
            frame: WindowFrame(
                x: windowX, y: windowY, width: windowWidth, height: windowHeight),
            sidebarWidth: sidebarWidth,
            activeTabID: activeTabID,
            tabs: tabs
        )
    }
}
```

- [ ] **Step 4: Point the two session functions at one window**

In `Sources/App/AppDelegate+Session.swift`, replace the `return SessionSnapshot(...)` at the end of `createSnapshot()` with:

```swift
        return SessionSnapshot(
            surfaceTintEnabled: surfaceTintEnabled,
            windows: [WindowSnapshot(
                windowID: singleWindowID,
                frame: WindowFrame(frame),
                sidebarWidth: sidebarWidth,
                activeTabID: tabStore.activeTabID,
                tabs: tabSnapshots
            )],
            keyWindowID: singleWindowID,
            repoColorOverrides: repoColorOverrides
        )
```

Add to `AppDelegate` in `Sources/App/AppDelegate.swift`, beside the other stored properties:

```swift
    /// Identifies this process's one window until the registry replaces it.
    let singleWindowID = UUID()
```

In `restoreSession(_:)`, replace the guard and the three assignments that follow it with:

```swift
        guard let app = ghostty.app, let windowSnap = snapshot.windows.first,
              !windowSnap.tabs.isEmpty else {
            // A quit that closed every window saves no windows, so this is a
            // normal cold launch and needs focus like any other.
            createTab()
            focusActiveSurface()
            return
        }

        sidebarWidth = windowSnap.sidebarWidth
        surfaceTintEnabled = snapshot.surfaceTintEnabled
        repoColorOverrides = snapshot.repoColorOverrides
```

Then replace `snapshot.tabs` with `windowSnap.tabs`, `snapshot.activeTabID` with `windowSnap.activeTabID`, and the frame block inside the `asyncAfter` with:

```swift
            let saved = windowSnap.frame
            if !saved.isEmpty {
                let visible = NSScreen.screens.map(\.visibleFrame)
                self.window?.setFrame(saved.clamped(toVisible: visible).rect, display: true)
            }
```

Add `import AppKit` to the top of the file if it is not already there.

- [ ] **Step 5: Run the tests and confirm they pass**

```bash
just check
```

Expected: all tests pass, zero SwiftLint violations.

- [ ] **Step 6: Verify against a real session file**

A synthetic fixture is what let the version 3 decode regression ship. Check the real file:

```bash
cp ~/Library/Application\ Support/montty/session.json /private/tmp/real-session.json
jq -r '"version=\(.version) tabs=\(.tabs | length)"' /private/tmp/real-session.json
```

Add this test to `Tests/SessionSnapshotV4Tests.swift`, using the values you just read, and confirm it passes:

```swift
    @Test func upgradesTheSessionFileOnThisMachine() throws {
        let path = "/private/tmp/real-session.json"
        guard let data = FileManager.default.contents(atPath: path) else {
            Issue.record("copy a real session.json to \(path) before running this")
            return
        }

        let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: data)

        #expect(snapshot.windows.count == 1)
        #expect(!snapshot.windows[0].tabs.isEmpty)
    }
```

Delete this test before committing. It depends on a file outside the repo, so it cannot live in the suite. Record in your report what version the real file was and how many tabs it held.

- [ ] **Step 7: Commit**

```bash
git add Sources/Persistence/SessionSnapshot.swift Sources/App/AppDelegate+Session.swift Sources/App/AppDelegate.swift Tests/SessionSnapshotV4Tests.swift
git commit -m "feat: session version 4 carries an array of windows"
```

---

### Task 4: WindowController owns a window

**Files:**
- Create: `Sources/App/WindowController.swift`
- Modify: `Sources/App/AppDelegate.swift:34` (remove `var window: NSWindow!`), `:14` (remove `let tabStore`), `:80-95` (window creation)
- Modify: `Sources/App/MainWindow.swift:1-45`

**Interfaces:**
- Consumes: `WindowModel` and `WindowRegistry` from Task 2.
- Produces: `WindowController(model:ghostty:appDelegate:)`, `WindowController.window: NSWindow`, `WindowController.model: WindowModel`, `WindowController.show()`, and `AppDelegate.registry: WindowRegistry`, `AppDelegate.controllers: [UUID: WindowController]`, `AppDelegate.keyController: WindowController?`.

This task keeps behavior identical. One window is created through the new type instead of inline, so the refactor is verifiable by the app looking and behaving exactly as before.

- [ ] **Step 1: Create the controller**

Create `Sources/App/WindowController.swift`:

```swift
// ABOUTME: Owns one NSWindow and the model state behind it, so the application
// ABOUTME: delegate no longer stands in for the single window it used to have.

import AppKit
import SwiftUI

final class WindowController: NSObject, NSWindowDelegate {
    let model: WindowModel
    let window: NSWindow
    private weak var appDelegate: AppDelegate?

    init(model: WindowModel, ghostty: Ghostty.App, appDelegate: AppDelegate) {
        self.model = model
        self.appDelegate = appDelegate
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.contentView = NSHostingView(rootView:
            MainWindow(window: model)
                .environmentObject(ghostty)
                .environmentObject(appDelegate)
        )
        window.title = "Montty"
        window.delegate = self
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        appDelegate?.registry.keyWindowID = model.id
    }

    func windowWillClose(_ notification: Notification) {
        appDelegate?.windowWillClose(self)
    }
}
```

- [ ] **Step 2: Give AppDelegate the registry**

In `Sources/App/AppDelegate.swift`, delete `let tabStore = TabStore()` and `var window: NSWindow!`, and add:

```swift
    let registry = WindowRegistry()
    var controllers: [UUID: WindowController] = [:]

    var keyController: WindowController? {
        guard let id = registry.keyWindow?.id else { return nil }
        return controllers[id]
    }

    /// The tabs of the window holding focus. Call sites that used to read the
    /// one and only store read this instead.
    var tabStore: TabStore {
        registry.keyWindow?.tabStore ?? TabStore()
    }
```

Keeping a `tabStore` accessor means the eight existing call sites still compile. Task 8 replaces the ones that must be window-aware.

- [ ] **Step 3: Create the first window through the controller**

In `applicationDidFinishLaunching`, replace the `NSHostingView` and `NSWindow` block (the lines from `let hostingView = NSHostingView(rootView:` through `NSApp.activate()`) with:

```swift
        let controller = makeWindow()
        controller.show()
        NSApp.activate()
```

Add to `AppDelegate`:

```swift
    /// Builds a window, registers it, and returns its controller. Every window
    /// in the process is created here.
    @discardableResult
    func makeWindow(_ model: WindowModel = WindowModel()) -> WindowController {
        registry.add(model)
        let controller = WindowController(
            model: model, ghostty: ghostty, appDelegate: self
        )
        controllers[model.id] = controller
        return controller
    }

    /// A window is going away. Drop it, and quit when it was the last one.
    func windowWillClose(_ controller: WindowController) {
        registry.remove(id: controller.model.id)
        controllers[controller.model.id] = nil
        if registry.windows.isEmpty {
            sessionStore.save(snapshot: createSnapshot())
            NSApp.terminate(nil)
        }
    }
```

`sessionStore` is `private` today. Change it to `private(set)` so the extension in `AppDelegate+Session.swift` and this method can reach it.

- [ ] **Step 4: Point the view at the window model**

In `Sources/App/MainWindow.swift`, change the declaration and the three per-window reads:

```swift
struct MainWindow: View {
    @EnvironmentObject var ghostty: Ghostty.App
    @EnvironmentObject var appDelegate: AppDelegate
    var window: WindowModel

    private var tabStore: TabStore { window.tabStore }
```

Replace every `appDelegate.sidebarWidth` in this file with `window.sidebarWidth`, including inside the drag gesture that assigns to it.

- [ ] **Step 5: Build and verify behavior is unchanged**

```bash
just check
```

Expected: all tests pass, zero SwiftLint violations. Then launch a scratch instance and confirm one window appears with its tabs and that the sidebar still drags:

```bash
mkdir -p /private/tmp/mw && MONTTY_SESSION_DIR=/private/tmp/mw MONTTY_SOCKET=/private/tmp/mw/h.sock ./tmp/montty-build/Debug/Montty.app/Contents/MacOS/Montty &
```

Record the PID you started. Kill only that PID when done. Never run `just stop`.

- [ ] **Step 6: Commit**

```bash
git add Sources/App/WindowController.swift Sources/App/AppDelegate.swift Sources/App/MainWindow.swift
git commit -m "refactor: give a window its own controller and model"
```

---

### Task 5: Cmd-N opens a window

**Files:**
- Modify: `Sources/App/AppDelegate.swift` (add `newWindow()`)
- Modify: `Sources/App/AppDelegate+GhosttyActions.swift:14-22` (observe the notification)
- Modify: `Sources/App/MenuBuilder.swift:131` (File menu item)

**Interfaces:**
- Consumes: `makeWindow(_:)` from Task 4.
- Produces: `func newWindow()` on `AppDelegate`.

The keybinding is not hardcoded. Menu items are built by `addAction(to:title:action:ctx:)`, which looks the shortcut up from the user's Ghostty config and forwards the action string to `ghostty_surface_binding_action`. Ghostty then posts a notification that montty observes. `Ghostty.Notification.ghosttyNewWindow` already exists in the vendored code and is posted for the `new_window` action; montty simply does not observe it yet. Wiring through it means Cmd-N comes from `~/.config/ghostty/config` like every other montty binding.

- [ ] **Step 1: Add the action**

In `Sources/App/AppDelegate.swift`:

```swift
    /// Opens a window with one tab, cascaded from the window in front so the new
    /// one does not land exactly on top of it.
    func newWindow() {
        let origin = keyController?.window.frame.origin
        let controller = makeWindow()
        if let origin {
            controller.window.setFrameTopLeftPoint(
                NSPoint(x: origin.x + 24, y: origin.y + controller.window.frame.height - 24)
            )
        }
        registry.keyWindowID = controller.model.id
        createTab()
        controller.show()
        focusActiveSurface()
    }
```

`createTab()` appends to `tabStore`, which now resolves to the key window's store, so setting `keyWindowID` before calling it is what puts the tab in the new window.

- [ ] **Step 2: Observe the Ghostty notification**

In `Sources/App/AppDelegate+GhosttyActions.swift`, in `observeTabActions(_:)` beside the `ghosttyNewTab` observer:

```swift
        center.addObserver(
            forName: Ghostty.Notification.ghosttyNewWindow,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.newWindow()
        }
```

- [ ] **Step 3: Add the menu item**

In `Sources/App/MenuBuilder.swift:131`, above the New Tab line:

```swift
        addAction(to: menu, title: "New Window", action: "new_window", ctx: ctx)
        menu.addItem(.separator())
```

The shortcut comes from the Ghostty config, so no key equivalent is written here. Ghostty binds `new_window` to Cmd-N by default.

- [ ] **Step 4: Verify by hand**

```bash
just check
```

Launch a scratch instance as in Task 4, press Cmd-N, and confirm a second window opens offset from the first with one tab in it, and that typing goes to the new window. Confirm the File menu shows New Window with Cmd-N beside it.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/AppDelegate.swift Sources/App/AppDelegate+GhosttyActions.swift Sources/App/MenuBuilder.swift
git commit -m "feat: open a window from ghostty's new-window action"
```

---

### Task 6: Save and restore every window

**Files:**
- Modify: `Sources/App/AppDelegate+Session.swift` (both functions)
- Create: `Tests/SessionRestoreShapeTests.swift`

**Interfaces:**
- Consumes: `WindowRegistry`, `WindowSnapshot`, `WindowFrame.clamped(toVisible:)`.
- Produces: `createSnapshot()` walking `registry.windows`, and `restoreSession(_:)` creating one controller per `WindowSnapshot`.

- [ ] **Step 1: Write the failing test**

Create `Tests/SessionRestoreShapeTests.swift`:

```swift
// ABOUTME: Verifies the snapshot records exactly the windows that are open, so
// ABOUTME: a window closed by hand does not come back on the next launch.

import Foundation
import Testing

@Suite struct SessionRestoreShapeTests {
    private func snapshot(of registry: WindowRegistry) -> SessionSnapshot {
        SessionSnapshot(
            surfaceTintEnabled: true,
            windows: registry.windows.map { window in
                WindowSnapshot(
                    windowID: window.id,
                    frame: window.frame,
                    sidebarWidth: window.sidebarWidth,
                    activeTabID: window.tabStore.activeTabID,
                    tabs: []
                )
            },
            keyWindowID: registry.keyWindowID,
            repoColorOverrides: [:]
        )
    }

    @Test func recordsEveryOpenWindow() {
        let registry = WindowRegistry()
        registry.add()
        registry.add()

        #expect(snapshot(of: registry).windows.count == 2)
    }

    @Test func forgetsAWindowThatWasClosed() {
        let registry = WindowRegistry()
        let first = registry.add()
        registry.add()

        registry.remove(id: first.id)

        let recorded = snapshot(of: registry)
        #expect(recorded.windows.count == 1)
        #expect(!recorded.windows.contains { $0.windowID == first.id })
    }

    @Test func recordsNoWindowsWhenEveryWindowIsClosed() {
        let registry = WindowRegistry()
        let only = registry.add()

        registry.remove(id: only.id)

        #expect(snapshot(of: registry).windows.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
just generate && just test 2>&1 | grep -E "SessionRestoreShapeTests|cannot find"
```

Expected: FAIL, because `snapshot(of:)` cannot be built until `WindowSnapshot` and `WindowRegistry` agree on these names. If both exist from Tasks 2 and 3, the test compiles and passes immediately. In that case, break it deliberately by removing the `registry.remove` line from `forgetsAWindowThatWasClosed`, confirm it fails, and restore it.

- [ ] **Step 3: Snapshot every window**

In `Sources/App/AppDelegate+Session.swift`, replace `createSnapshot()` with:

```swift
    func createSnapshot() -> SessionSnapshot {
        SessionSnapshot(
            surfaceTintEnabled: surfaceTintEnabled,
            windows: registry.windows.map { window in
                WindowSnapshot(
                    windowID: window.id,
                    frame: WindowFrame(controllers[window.id]?.window.frame ?? .zero),
                    sidebarWidth: window.sidebarWidth,
                    activeTabID: window.tabStore.activeTabID,
                    tabs: window.tabStore.tabs.map(tabSnapshot(of:))
                )
            },
            keyWindowID: registry.keyWindowID,
            repoColorOverrides: repoColorOverrides
        )
    }

    /// One tab's persisted shape, including each leaf's working directory and
    /// color override keyed by leaf rather than by the surface id, which is
    /// minted fresh on restore.
    private func tabSnapshot(of tab: Tab) -> TabSnapshot {
        var dirs: [UUID: String] = [:]
        var colors: [UUID: PaneTint] = [:]
        for leaf in SplitTree.allLeaves(node: tab.splitRoot) {
            if let pwd = surfaceView(for: leaf.surfaceID)?.pwd {
                dirs[leaf.id] = pwd
            }
            if let tint = tab.surfaceColorOverrides[leaf.surfaceID] {
                colors[leaf.id] = tint
            }
        }
        return TabSnapshot(
            tabID: tab.id,
            name: tab.name,
            position: tab.position,
            focusedLeafID: tab.focusedLeafID,
            splitLayout: tab.splitRoot,
            leafDirectories: dirs,
            leafColorOverrides: colors,
            colorOverride: tab.colorOverride
        )
    }
```

- [ ] **Step 4: Restore every window**

Replace `restoreSession(_:)` with:

```swift
    func restoreSession(_ snapshot: SessionSnapshot) {
        let restorable = snapshot.windows.filter { !$0.tabs.isEmpty }
        guard let app = ghostty.app, !restorable.isEmpty else {
            // A quit that closed every window saves no windows, so this is a
            // normal cold launch and needs focus like any other.
            let controller = makeWindow()
            controller.show()
            createTab()
            focusActiveSurface()
            return
        }

        surfaceTintEnabled = snapshot.surfaceTintEnabled
        repoColorOverrides = snapshot.repoColorOverrides

        for windowSnap in restorable {
            let model = WindowModel(
                id: windowSnap.windowID,
                sidebarWidth: windowSnap.sidebarWidth,
                frame: windowSnap.frame
            )
            let controller = makeWindow(model)
            for tabSnap in windowSnap.tabs.sorted(by: { $0.position < $1.position }) {
                let tab = Tab(
                    id: tabSnap.tabID, name: tabSnap.name, position: tabSnap.position
                )
                tab.splitRoot = restoreSplitNode(
                    tabSnap.splitLayout,
                    directories: tabSnap.leafDirectories,
                    colors: tabSnap.leafColorOverrides,
                    app: app, tab: tab
                )
                tab.focusedLeafID = tabSnap.focusedLeafID
                tab.colorOverride = tabSnap.colorOverride
                model.tabStore.append(tab: tab)
            }
            model.tabStore.activeTabID =
                windowSnap.activeTabID ?? model.tabStore.tabs.first?.id
            controller.show()
        }

        registry.keyWindowID = snapshot.keyWindowID ?? registry.windows.first?.id
        keyController?.window.makeKeyAndOrderFront(nil)

        // Frames and focus settle after SwiftUI lays the hierarchy out. Each
        // surface calls becomeFirstResponder when it joins a window, so focus
        // needs the last word.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            let visible = NSScreen.screens.map(\.visibleFrame)
            for window in self.registry.windows where !window.frame.isEmpty {
                self.controllers[window.id]?.window.setFrame(
                    window.frame.clamped(toVisible: visible).rect, display: true
                )
            }
            self.syncSurfaceFocus()
            self.focusActiveSurface()
        }
    }
```

- [ ] **Step 5: Run tests and verify by hand**

```bash
just check
```

Then, in a scratch instance: open a second window with Cmd-N, quit with Cmd-Q, relaunch, and confirm both windows return with their tabs. Then close one window, quit, relaunch, and confirm only the remaining window returns.

- [ ] **Step 6: Commit**

```bash
git add Sources/App/AppDelegate+Session.swift Tests/SessionRestoreShapeTests.swift
git commit -m "feat: save and restore every open window"
```

---

### Task 7: Window title follows the active tab

**Files:**
- Modify: `Sources/App/WindowController.swift`
- Modify: `Sources/App/AppDelegate.swift` (call the sync where the active tab changes)

**Interfaces:**
- Consumes: `Tab.tabInfo.displayName` and `WindowModel`.
- Produces: `WindowController.syncTitle()`.

- [ ] **Step 1: Add the sync**

In `Sources/App/WindowController.swift`:

```swift
    /// The window takes its name from the tab in front, so two windows are
    /// distinguishable in the Window menu and in Mission Control.
    func syncTitle() {
        let name = model.tabStore.activeTab?.displayName ?? ""
        window.title = name.isEmpty ? "Montty" : name
    }
```

`Tab.displayName` is at `Sources/Model/Tab.swift:37` and returns `name` when the tab has been named, otherwise `autoName`.

Call it at the end of `init` after the hosting view is set, and from `windowDidBecomeKey`.

- [ ] **Step 2: Call it when the active tab changes**

In `Sources/App/AppDelegate.swift`, in `selectTab(id:)`, `createTab()`, and `closeTab(id:)`, add as the last line:

```swift
        keyController?.syncTitle()
```

`Sources/App/AppDelegate.swift:429` assigns `tab?.autoName = title` when a surface reports a new terminal title. Add the sync there, resolving the window that owns that surface rather than the key window, so a background window's title tracks its own shell:

```swift
                if let owner = self.registry.locate(surfaceID: id)?.window {
                    self.controllers[owner.id]?.syncTitle()
                }
```

- [ ] **Step 3: Verify by hand**

```bash
just check
```

In a scratch instance, confirm the window title shows the active tab's name, changes when you switch tabs, and that two windows show different titles in the Window menu.

- [ ] **Step 4: Commit**

```bash
git add Sources/App/WindowController.swift Sources/App/AppDelegate.swift
git commit -m "feat: name a window after the tab in front of it"
```

---

### Task 8: Route subsystems through the registry

**Files:**
- Modify: `Sources/App/HookServer.swift:185`, `:223`
- Modify: `Sources/App/DebugServerHandlers.swift:74`, `:90-91`, `:177`, `:527`
- Modify: `Sources/App/AppDelegate+Focus.swift:18`
- Modify: `Sources/App/AppDelegate+GhosttyActions.swift` (13 `tabStore` references)
- Modify: `Sources/App/AppDelegate.swift` (remove the temporary `tabStore` accessor)

**Interfaces:**
- Consumes: `registry.locate(surfaceID:)` and `registry.keyWindow` from Task 2.
- Produces: no new API. Every site that meant "the one window" now names which window it means.

- [ ] **Step 1: Convert the surface lookups**

Each of these sites searches `tabStore.tabs` for the tab holding a surface. Replace the search with the registry. For example, `HookServer.swift:223` currently reads:

```swift
            let owningTab = appDelegate.tabStore.tabs.first { tab in
```

Replace with:

```swift
            let owningTab = appDelegate.registry.locate(surfaceID: surfaceID)?.tab
```

Apply the same conversion at `HookServer.swift:185`, `DebugServerHandlers.swift:527`, and any other site whose search body is a `SplitTree.findLeaf` over the tab's split root. A surface lookup must never be scoped to one window.

- [ ] **Step 2: Convert the "current window" reads**

Sites that mean "whatever window has focus" become `registry.keyWindow?.tabStore`. That covers `AppDelegate+Focus.swift:18`, `DebugServerHandlers.swift:74`, and every reference in `AppDelegate+GhosttyActions.swift`, because a Ghostty action always applies to the window that produced it.

- [ ] **Step 3: Enumerate every window where the old code enumerated tabs**

`DebugServerHandlers.swift:90` and `:177` loop over `appDelegate.tabStore.tabs`. Both must loop over every window:

```swift
            for window in appDelegate.registry.windows {
                for tab in window.tabStore.tabs {
                    let isActiveTab = tab.id == window.tabStore.activeTabID
```

- [ ] **Step 4: Route the menu action dispatcher**

`handleMenuAction(_:)` at `Sources/App/AppDelegate.swift:462` forwards a Ghostty action string to the focused surface, and reads `tabStore.activeTab` to find it. Every menu command flows through this one function, so routing it is the whole menu audit:

```swift
    @objc func handleMenuAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? String,
              let tab = registry.keyWindow?.tabStore.activeTab,
              let surfaceID = tab.focusedSurfaceID,
              let view = surfaceView(for: surfaceID),
              let surface = view.surface else { return }
        ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }
```

The other menu handlers named in `MenuBuilder.swift` are `openConfig`, `enterJumpMode`, `sidebarVisible.toggle()`, and `surfaceTintEnabled.toggle()`. The first is app-wide, the second is Task 10, and the last two are app-wide toggles that stay on `AppDelegate`.

- [ ] **Step 5: Delete the temporary accessor**

Remove the `var tabStore: TabStore` computed property added to `AppDelegate` in Task 4. The build failing is the point: every remaining use is a site that has not yet said which window it means. Fix each one, then confirm:

```bash
grep -rn 'appDelegate\.tabStore\|appDel\.tabStore\|self\.tabStore' Sources/ | grep -v '^Sources/Ghostty/'
```

Expected: no output.

- [ ] **Step 6: Run the tests**

```bash
just check
```

Expected: all tests pass, zero SwiftLint violations.

- [ ] **Step 7: Verify a development build still runs beside the host montty**

`just run` sets `MONTTY_SESSION_DIR` and `MONTTY_SOCKET` under the build
directory, and the instance guard derives its lock from the socket path, so a
development build must take a different lock and leave the installed montty
alone. This work must not change that.

```bash
ps aux | grep -c '[M]ontty.app/Contents/MacOS/Montty'
just run-bg
ps aux | grep -c '[M]ontty.app/Contents/MacOS/Montty'
ls /tmp/montty-build/hook.sock /tmp/montty-build/hook.sock.lock
```

Expected: the count rises by exactly one, and the development build owns its own
socket and lock under `/tmp/montty-build`. Kill only the PID you started. Never
run `just stop`.

- [ ] **Step 8: Commit**

```bash
git add Sources/App/
git commit -m "refactor: name the window every subsystem lookup means"
```

---

### Task 9: Window identity in the debug server

**Files:**
- Modify: `Sources/App/DebugServerHandlers.swift` (the `/surfaces` payload)
- Modify: `justfile` (`inspect-screenshot`, new `inspect-windows`)
- Modify: `docs/debug-server.md`

**Interfaces:**
- Consumes: `registry.windows` and `registry.keyWindowID`.
- Produces: `window_id`, `window_is_key` on each `/surfaces` entry, and a `just inspect-windows` recipe.

- [ ] **Step 1: Add window identity to the payload**

In the `/surfaces` handler in `Sources/App/DebugServerHandlers.swift`, inside the loop from Task 8 step 3, add to each surface object:

```swift
                    "window_id": window.id.uuidString,
                    "window_is_key": window.id == appDelegate.registry.keyWindowID,
```

- [ ] **Step 2: Raise the owning window before a screenshot**

`inspect-screenshot` activates the application by name, which raises the app but not the window holding the requested surface, so a surface in a background window is captured occluded. In the `/screenshot` handler, before capturing, bring the owning window forward:

```swift
        if let located = appDelegate.registry.locate(surfaceID: surfaceID) {
            appDelegate.controllers[located.window.id]?.window.makeKeyAndOrderFront(nil)
        }
```

- [ ] **Step 3: Add the recipe**

In `justfile`, beside the other inspect recipes:

```make
# List open windows with their key state and tab count
inspect-windows:
    @curl -sf localhost:9876/surfaces | jq 'group_by(.window_id) | map({window_id: .[0].window_id, is_key: .[0].window_is_key, surfaces: length})'
```

- [ ] **Step 4: Document it**

In `docs/debug-server.md`, in the `GET /surfaces` section, add `window_id` and `window_is_key` to the field list, and add `inspect-windows` to the recipe table. State that `/screenshot` raises the window owning the requested surface.

- [ ] **Step 5: Verify against a running instance**

```bash
just check
```

Launch a scratch Debug instance, open two windows, then:

```bash
just inspect-windows
```

Expected: two entries, exactly one with `is_key: true`. Take a screenshot of a surface in the background window and confirm the captured image shows that window rather than the one in front.

- [ ] **Step 6: Commit**

```bash
git add Sources/App/DebugServerHandlers.swift justfile docs/debug-server.md
git commit -m "feat: attribute every inspected surface to its window"
```

---

### Task 10: Jump mode stays in the key window

**Files:**
- Modify: `Sources/App/AppDelegate.swift` (`enterJumpMode`, `jumpToSurface`)

**Interfaces:**
- Consumes: `registry.keyWindow`.
- Produces: no new API.

- [ ] **Step 1: Scope label assignment**

`enterJumpMode()` at `Sources/App/AppDelegate.swift:334` collects targets from `tabStore.activeTabID` and `tabStore.activeTab`, then from the other tabs. Task 8 deleted the `tabStore` accessor, so this function must name its window. Bind it once at the top and use it throughout:

```swift
    func enterJumpMode() {
        // Jump moves focus inside the window in front of you. Labeling every
        // leaf in every window would make the label set larger and its labels
        // longer for no gain.
        guard let store = registry.keyWindow?.tabStore else { return }
        var targets: [JumpTarget] = []
        let activeID = store.activeTabID

        if let activeTab = store.activeTab {
```

Replace the remaining `tabStore` references in the body with `store`. Apply the same binding to `jumpToSurface(tabID:leafID:)` so a label resolves in the window that assigned it.

- [ ] **Step 2: Verify by hand**

```bash
just check
```

In a scratch instance with two windows each holding a split, enter jump mode and confirm labels appear only in the focused window, and that jumping moves focus within it.

- [ ] **Step 3: Commit**

```bash
git add Sources/App/AppDelegate.swift
git commit -m "fix: label only the focused window in jump mode"
```

---

### Task 11: Documentation

**Files:**
- Modify: `README.md`, `CLAUDE.md`, `docs/montty-cli.md`

**Interfaces:** none.

- [ ] **Step 1: Correct the single-window rule**

`CLAUDE.md` states "Single window app. No multi-window support." Replace with:

```markdown
- One process, many windows. Cmd-N opens a window that owns its own tabs and
  splits. Tabs do not move between windows.
```

- [ ] **Step 2: Describe the behavior**

In `README.md`, beside the session files section, state that the windows open at quit are the windows restored on launch, and that a window closed by hand is not restored.

- [ ] **Step 3: Note the scope boundary**

In `docs/montty-cli.md`, state that every command targets the surface it runs in, which resolves regardless of which window holds it, and that there is no window scope.

- [ ] **Step 4: Verify and commit**

```bash
just check
grep -rn '—\|–' README.md CLAUDE.md docs/montty-cli.md
```

Expected: no em-dashes or en-dashes.

```bash
git add README.md CLAUDE.md docs/montty-cli.md
git commit -m "docs: describe windows and what a quit restores"
```
