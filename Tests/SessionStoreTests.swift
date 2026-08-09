// ABOUTME: Tests for SessionStore's version gate and quarantine behavior --
// ABOUTME: an unreadable or too-new file is protected before the next save.

import Foundation
import Testing

@Suite struct SessionStoreTests {
    private func tempDir() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("montty-store-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func loadsAV2SessionWithBareStringColors() throws {
        let dir = tempDir()
        let json = """
        {"version":2,"windowX":0,"windowY":0,"windowWidth":100,"windowHeight":100,
         "activeTabID":null,"tabs":[],"repoColorOverrides":{"/repo":"green"}}
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("session.json"))

        let snapshot = SessionStore(directory: dir).load()
        #expect(snapshot?.repoColorOverrides["/repo"] == PaneTint(stops: [.named(.green)]))
    }

    @Test func refusesASessionFromANewerVersion() throws {
        let dir = tempDir()
        let json = """
        {"version":99,"windowX":0,"windowY":0,"windowWidth":100,"windowHeight":100,
         "activeTabID":null,"tabs":[]}
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("session.json"))

        #expect(SessionStore(directory: dir).load() == nil)
    }

    @Test func quarantinesAnUnparseableFileInsteadOfOverwritingIt() throws {
        let dir = tempDir()
        let path = dir.appendingPathComponent("session.json")
        try Data("{ not json".utf8).write(to: path)

        let store = SessionStore(directory: dir)
        #expect(store.load() == nil)
        store.save(snapshot: SessionSnapshot(tabs: []))

        let names = try FileManager.default
            .contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("session.corrupt-") }
        #expect(names.count == 1)

        let quarantined = try String(
            contentsOf: dir.appendingPathComponent(names[0]), encoding: .utf8
        )
        #expect(quarantined == "{ not json")
    }

    @Test func backsUpThePreviousFileWhenTheVersionChanges() throws {
        let dir = tempDir()
        let json = """
        {"version":2,"windowX":0,"windowY":0,"windowWidth":100,"windowHeight":100,
         "activeTabID":null,"tabs":[]}
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("session.json"))

        let store = SessionStore(directory: dir)
        _ = store.load()
        store.save(snapshot: SessionSnapshot(tabs: []))

        let backup = dir.appendingPathComponent("session.v2.json")
        #expect(FileManager.default.fileExists(atPath: backup.path))
    }

    @Test func roundTripsGradientOverrides() throws {
        let dir = tempDir()
        let store = SessionStore(directory: dir)
        let tint = PaneTint(stops: [.named(.neutralBright), .hex(RGB(r: 0x1A, g: 0x7F, b: 0x37))])
        store.save(snapshot: SessionSnapshot(
            tabs: [], repoColorOverrides: ["/repo": tint]
        ))
        #expect(store.load()?.repoColorOverrides["/repo"] == tint)
    }

    @Test func saveAndLoadRoundTrip() throws {
        let dir = tempDir()
        let store = SessionStore(directory: dir)
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
        let store = SessionStore(directory: tempDir())
        let result = store.load()
        #expect(result == nil)
    }

    @Test func resolveDirectoryUsesEnvironmentOverride() {
        let url = SessionStore.resolveDirectory(
            environment: ["MONTTY_SESSION_DIR": "/tmp/montty-test-session"]
        )

        #expect(url.path == "/tmp/montty-test-session")
    }

    @Test func resolveDirectoryExpandsTilde() {
        let url = SessionStore.resolveDirectory(
            environment: ["MONTTY_SESSION_DIR": "~/montty-test-session"]
        )

        // Assert the real home directory was substituted. Checking only for the
        // absence of "~" would pass for a resolver that merely strips the character.
        #expect(url.path == "\(NSHomeDirectory())/montty-test-session")
    }

    @Test func resolveDirectoryIgnoresEmptyOverride() {
        let url = SessionStore.resolveDirectory(environment: ["MONTTY_SESSION_DIR": ""])

        #expect(url.path.hasSuffix("/montty"))
    }

    @Test func resolveDirectoryFallsBackToApplicationSupport() {
        let url = SessionStore.resolveDirectory(environment: [:])

        #expect(url.path.hasSuffix("/montty"))
        #expect(url.path.contains("Application Support"))
    }
}
