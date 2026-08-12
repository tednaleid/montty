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

    @Test func decodesAV4WindowMissingEachOptionalFieldUsingDefaults() throws {
        let tabID = UUID()

        func fullFields() -> [String: String] {
            [
                "windowID": "\"\(UUID().uuidString)\"",
                "frame": #"{"x": 10, "y": 20, "width": 300, "height": 400}"#,
                "sidebarWidth": "250",
                "activeTabID": "\"\(tabID.uuidString)\"",
                "tabs": "[]"
            ]
        }

        func decodeWindow(omitting key: String) throws -> WindowSnapshot {
            var fields = fullFields()
            fields.removeValue(forKey: key)
            let body = fields.map { "\"\($0.key)\": \($0.value)" }.joined(separator: ",")
            let snapshot = try decode(#"{"version": 4, "windows": [{\#(body)}]}"#)
            #expect(snapshot.windows.count == 1)
            return snapshot.windows[0]
        }

        // windowID has no meaningful default to assert beyond "decoding
        // succeeds", since the fallback mints a fresh random UUID.
        _ = try decodeWindow(omitting: "windowID")

        #expect(
            try decodeWindow(omitting: "frame").frame
                == WindowFrame(x: 0, y: 0, width: 0, height: 0)
        )
        #expect(try decodeWindow(omitting: "sidebarWidth").sidebarWidth == 200)
        #expect(try decodeWindow(omitting: "activeTabID").activeTabID == nil)
        #expect(try decodeWindow(omitting: "tabs").tabs.isEmpty)
    }

    @Test func treatsAMissingWindowsKeyAsALegacyFileWithNoWindows() throws {
        let snapshot = try decode(#"{"version": 4, "surfaceTintEnabled": true}"#)

        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.version == 4)
    }

    /// App-wide settings belong to the session, not to any window, so a file
    /// that saved no windows -- what closing the last one by hand writes --
    /// still carries them.
    @Test func keepsAppWideSettingsInAFileWithNoWindows() throws {
        let json = #"{"version": 4, "windows": [], "surfaceTintEnabled": false, "#
            + #""repoColorOverrides": {"/Users/dev/work/alpha": "blue"}}"#
        let snapshot = try decode(json)

        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.surfaceTintEnabled == false)
        #expect(
            snapshot.repoColorOverrides["/Users/dev/work/alpha"]
                == PaneTint(stops: [.named(.blue)])
        )
    }

    @Test func decodesAnExplicitEmptyWindowsArrayAsNoWindows() throws {
        let snapshot = try decode(#"{"version": 4, "windows": []}"#)

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
