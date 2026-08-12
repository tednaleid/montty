import Foundation
import Testing

struct SessionSnapshotTests {
    @Test func roundTripSimpleSession() throws {
        let leafID = UUID()
        let tabID = UUID()
        let snapshot = SessionSnapshot(
            windows: [WindowSnapshot(
                windowID: UUID(), frame: WindowFrame(x: 100, y: 100, width: 1200, height: 800),
                sidebarWidth: 220, activeTabID: tabID,
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
            )]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)

        #expect(decoded.version == 4)
        #expect(decoded.windows[0].tabs.count == 1)
        #expect(decoded.windows[0].tabs[0].name == "my project")
        #expect(decoded.windows[0].activeTabID == tabID)
        #expect(decoded.windows[0].sidebarWidth == 220)
        #expect(decoded.windows[0].tabs[0].leafDirectories[leafID] == "/Users/ted/projects")
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
            windows: [WindowSnapshot(
                windowID: UUID(), frame: WindowFrame(x: 0, y: 0, width: 0, height: 0),
                sidebarWidth: 200, activeTabID: tabID,
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
            )]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)

        guard case .split(let branch) = decoded.windows[0].tabs[0].splitLayout else {
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
            windows: [WindowSnapshot(
                windowID: UUID(), frame: WindowFrame(x: 0, y: 0, width: 1920, height: 1080),
                sidebarWidth: 250, activeTabID: tabs[2].tabID,
                tabs: tabs
            )]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)

        #expect(decoded.windows[0].tabs.count == 5)
        #expect(decoded.windows[0].tabs.map(\.position) == [0, 1, 2, 3, 4])
        #expect(decoded.windows[0].activeTabID == tabs[2].tabID)
    }

    @Test func decodesVersionField() throws {
        let leafID = UUID()
        let snapshot = SessionSnapshot(
            windows: [WindowSnapshot(
                windowID: UUID(), frame: WindowFrame(x: 0, y: 0, width: 800, height: 600),
                sidebarWidth: 200, activeTabID: nil,
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
            )]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)
        #expect(decoded.version == 4)
    }

    @Test func roundTripRepoColorOverrides() throws {
        let leafID = UUID()
        let overrides: [String: PaneTint] = [
            "/Users/ted/montty": PaneTint(stops: [.named(.blue)]),
            "/Users/ted/limn": PaneTint(stops: [.named(.red)])
        ]
        let snapshot = SessionSnapshot(
            windows: [WindowSnapshot(
                windowID: UUID(), frame: WindowFrame(x: 0, y: 0, width: 800, height: 600),
                sidebarWidth: 200, activeTabID: nil,
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
            )],
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
            windows: [WindowSnapshot(
                windowID: UUID(), frame: WindowFrame(x: 0, y: 0, width: 800, height: 600),
                sidebarWidth: 200, activeTabID: nil,
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
            )],
            repoColorOverrides: ["/some/path": PaneTint(stops: [.named(.blue)])]
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

    @Test func leafColorOverridesRoundTrip() throws {
        let leafID = UUID()
        let tint = PaneTint(stops: [.named(.blue), .named(.red)])
        let snapshot = SessionSnapshot(windows: [WindowSnapshot(
            windowID: UUID(), frame: WindowFrame(x: 0, y: 0, width: 0, height: 0),
            sidebarWidth: 200, activeTabID: nil,
            tabs: [
                TabSnapshot(
                    tabID: UUID(), name: "review", position: 0,
                    focusedLeafID: leafID,
                    splitLayout: .leaf(SurfaceLeaf(id: leafID, surfaceID: UUID())),
                    leafDirectories: [:],
                    leafColorOverrides: [leafID: tint],
                    colorOverride: nil
                )
            ]
        )])
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)
        #expect(decoded.windows[0].tabs[0].leafColorOverrides[leafID] == tint)
        #expect(decoded.version == 4)
    }

    @Test func decodesAV2TabMissingLeafColorOverrides() throws {
        let tabID = UUID()
        let leafID = UUID()
        let surfaceID = UUID()
        let json = """
        {"version":2,"windowX":0,"windowY":0,"windowWidth":800,"windowHeight":600,
         "activeTabID":"\(tabID)","tabs":[
           {"tabID":"\(tabID)","name":"review","position":0,
            "focusedLeafID":"\(leafID)",
            "splitLayout":{"type":"leaf","leaf":{"id":"\(leafID)","surfaceID":"\(surfaceID)"}},
            "leafDirectories":["\(leafID)","/tmp/review"],
            "colorOverride":"blue"}
         ]}
        """

        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: Data(json.utf8))

        #expect(decoded.windows.count == 1)
        #expect(decoded.windows[0].tabs.count == 1)
        #expect(decoded.windows[0].tabs[0].name == "review")
        guard case .leaf(let leaf) = decoded.windows[0].tabs[0].splitLayout else {
            Issue.record("Expected leaf split layout")
            return
        }
        #expect(leaf.id == leafID)
        #expect(decoded.windows[0].tabs[0].leafColorOverrides.isEmpty)
        #expect(decoded.windows[0].tabs[0].colorOverride == PaneTint(stops: [.named(.blue)]))
    }
}
