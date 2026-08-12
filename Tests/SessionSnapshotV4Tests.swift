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
                "type": "leaf",
                "leaf": {
                  "id": "\(leafID.uuidString)",
                  "surfaceID": "\(surfaceID.uuidString)"
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
