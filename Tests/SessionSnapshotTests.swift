import Foundation
import Testing

struct SessionSnapshotTests {
    @Test func roundTripSimpleSession() throws {
        let leafID = UUID()
        let tabID = UUID()
        let snapshot = SessionSnapshot(
            windowX: 100, windowY: 100, windowWidth: 1200, windowHeight: 800,
            sidebarWidth: 220,
            activeTabID: tabID,
            tabs: [
                TabSnapshot(
                    tabID: tabID,
                    name: "my project",
                    position: 0,
                    focusedLeafID: leafID,
                    splitLayout: .leaf(SurfaceLeaf(id: leafID)),
                    leafDirectories: [leafID: "/Users/ted/projects"]
                )
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)

        #expect(decoded.version == 2)
        #expect(decoded.tabs.count == 1)
        #expect(decoded.tabs[0].name == "my project")
        #expect(decoded.activeTabID == tabID)
        #expect(decoded.sidebarWidth == 220)
        #expect(decoded.tabs[0].leafDirectories[leafID] == "/Users/ted/projects")
    }

    @Test func roundTripSplitLayout() throws {
        let leaf1 = SurfaceLeaf()
        let leaf2 = SurfaceLeaf()
        let split = SplitBranch(
            orientation: .horizontal,
            ratio: 0.6,
            first: .leaf(leaf1),
            second: .leaf(leaf2)
        )
        let tabID = UUID()
        let snapshot = SessionSnapshot(
            windowX: 0, windowY: 0, windowWidth: 0, windowHeight: 0,
            sidebarWidth: 200,
            activeTabID: tabID,
            tabs: [
                TabSnapshot(
                    tabID: tabID,
                    name: "",
                    position: 0,
                    focusedLeafID: leaf1.id,
                    splitLayout: .split(split),
                    leafDirectories: [
                        leaf1.id: "/tmp/a",
                        leaf2.id: "/tmp/b"
                    ]
                )
            ]
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
        let tabs = (0..<5).map { idx in
            let leafID = UUID()
            return TabSnapshot(
                tabID: UUID(),
                name: "tab \(idx)",
                position: idx,
                focusedLeafID: leafID,
                splitLayout: .leaf(SurfaceLeaf(id: leafID)),
                leafDirectories: [leafID: "/tmp/\(idx)"]
            )
        }
        let snapshot = SessionSnapshot(
            windowX: 0, windowY: 0, windowWidth: 1920, windowHeight: 1080,
            sidebarWidth: 250,
            activeTabID: tabs[2].tabID,
            tabs: tabs
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)

        #expect(decoded.tabs.count == 5)
        #expect(decoded.tabs.map(\.position) == [0, 1, 2, 3, 4])
        #expect(decoded.activeTabID == tabs[2].tabID)
    }

    @Test func decodesVersionField() throws {
        let leafID = UUID()
        let snapshot = SessionSnapshot(
            windowX: 0, windowY: 0, windowWidth: 800, windowHeight: 600,
            sidebarWidth: 200,
            tabs: [
                TabSnapshot(
                    tabID: UUID(),
                    name: "",
                    position: 0,
                    focusedLeafID: leafID,
                    splitLayout: .leaf(SurfaceLeaf(id: leafID)),
                    leafDirectories: [:]
                )
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)
        #expect(decoded.version == 2)
    }

    @Test func roundTripRepoColorOverrides() throws {
        let leafID = UUID()
        let overrides: [String: TabColor] = [
            "/Users/ted/montty": .blue,
            "/Users/ted/limn": .red
        ]
        let snapshot = SessionSnapshot(
            windowX: 0, windowY: 0, windowWidth: 800, windowHeight: 600,
            sidebarWidth: 200,
            tabs: [
                TabSnapshot(
                    tabID: UUID(),
                    name: "",
                    position: 0,
                    focusedLeafID: leafID,
                    splitLayout: .leaf(SurfaceLeaf(id: leafID)),
                    leafDirectories: [:]
                )
            ],
            repoColorOverrides: overrides
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)
        #expect(decoded.repoColorOverrides == overrides)
    }

    @Test func missingOverridesDecodesAsEmpty() throws {
        // Encode a snapshot, strip repoColorOverrides, verify it decodes with empty
        let leafID = UUID()
        let snapshot = SessionSnapshot(
            windowX: 0, windowY: 0, windowWidth: 800, windowHeight: 600,
            sidebarWidth: 200,
            tabs: [
                TabSnapshot(
                    tabID: UUID(),
                    name: "",
                    position: 0,
                    focusedLeafID: leafID,
                    splitLayout: .leaf(SurfaceLeaf(id: leafID)),
                    leafDirectories: [:]
                )
            ],
            repoColorOverrides: ["/some/path": .blue]
        )
        let data = try JSONEncoder().encode(snapshot)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Expected dictionary")
            return
        }
        json.removeValue(forKey: "repoColorOverrides")
        let strippedData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: strippedData)
        #expect(decoded.repoColorOverrides.isEmpty)
    }
}

struct SessionStoreTests {
    @Test func saveAndLoadRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SessionStore(directory: tempDir)
        let leafID = UUID()
        let snapshot = SessionSnapshot(
            windowX: 50, windowY: 50, windowWidth: 1000, windowHeight: 700,
            sidebarWidth: 230,
            activeTabID: nil,
            tabs: [
                TabSnapshot(
                    tabID: UUID(),
                    name: "",
                    position: 0,
                    focusedLeafID: leafID,
                    splitLayout: .leaf(SurfaceLeaf(id: leafID)),
                    leafDirectories: [:]
                )
            ]
        )

        store.save(snapshot: snapshot)
        let loaded = store.load()

        #expect(loaded != nil)
        #expect(loaded?.sidebarWidth == 230)
        #expect(loaded?.windowWidth == 1000)
    }

    @Test func loadFromEmptyDirectoryReturnsNil() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SessionStore(directory: tempDir)
        let result = store.load()
        #expect(result == nil)
    }
}
