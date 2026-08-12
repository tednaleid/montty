// ABOUTME: Decodes session files copied out of a real Application Support
// ABOUTME: directory, so migration is checked against shapes montty itself wrote.

import Foundation
import Testing

/// Anchors `Bundle(for:)` on the test bundle, which is where the fixture JSON
/// lands. Swift Testing suites are structs, so a class is needed for the lookup.
private final class FixtureBundle {}

/// The fixtures are verbatim copies of `session.json` and its version backup
/// from an Application Support directory, with only the working directories
/// rewritten to generic paths. Every key, nesting level, and optional field is
/// exactly as montty wrote it, which is the point: a hand-written fixture is
/// what let a decode regression ship once already.
@Suite struct RealSessionFileTests {
    private func fixture(_ name: String) throws -> SessionSnapshot {
        let url = try #require(
            Bundle(for: FixtureBundle.self).url(forResource: name, withExtension: "json")
        )
        return try JSONDecoder().decode(SessionSnapshot.self, from: Data(contentsOf: url))
    }

    /// The two leaves of a tab whose saved layout is a split branch.
    private func branchLeaves(_ tab: TabSnapshot) throws -> (SurfaceLeaf, SurfaceLeaf) {
        guard case .split(let branch) = tab.splitLayout else {
            Issue.record("tab at position \(tab.position) decoded as a leaf, not a branch")
            throw DecodeShapeError.notABranch
        }
        guard case .leaf(let first) = branch.first, case .leaf(let second) = branch.second else {
            Issue.record("branch in tab at position \(tab.position) lost a leaf")
            throw DecodeShapeError.missingLeaf
        }
        return (first, second)
    }

    private enum DecodeShapeError: Error {
        case notABranch
        case missingLeaf
    }

    @Test func migratesTheRealVersionThreeFileIntoOneWindow() throws {
        let snapshot = try fixture("session-v3-real")

        #expect(snapshot.version == 3)
        #expect(snapshot.windows.count == 1)
        let window = try #require(snapshot.windows.first)
        #expect(window.tabs.count == 3)
        #expect(window.frame == WindowFrame(x: 661, y: 39, width: 2089, height: 2121))
        #expect(window.sidebarWidth == 200)
        #expect(window.activeTabID == UUID(uuidString: "8DEA4477-4FF2-4114-BEF3-970E7168A8CF"))
        #expect(snapshot.keyWindowID == window.windowID)
        #expect(snapshot.surfaceTintEnabled)
    }

    @Test func keepsBothLeavesOfEveryRealSplitBranch() throws {
        let snapshot = try fixture("session-v3-real")
        let window = try #require(snapshot.windows.first)

        for tab in window.tabs {
            let (first, second) = try branchLeaves(tab)
            #expect(first.id != second.id)
            #expect(first.surfaceID != second.surfaceID)
            #expect(tab.focusedLeafID == first.id)
        }
    }

    @Test func keepsEveryRealLeafsDirectory() throws {
        let snapshot = try fixture("session-v3-real")
        let window = try #require(snapshot.windows.first)

        let directories = try window.tabs.map { tab -> [String] in
            let (first, second) = try branchLeaves(tab)
            #expect(tab.leafDirectories.count == 2)
            return [tab.leafDirectories[first.id], tab.leafDirectories[second.id]]
                .compactMap { $0 }
        }

        #expect(directories == [
            ["/Users/dev/work/alpha", "/Users/dev/work/alpha"],
            ["/Users/dev/work/beta", "/Users/dev/work/beta"],
            ["/Users/dev/work/gamma", "/Users/dev/work/gamma"]
        ])
    }

    /// The real v3 file writes `leafColorOverrides` as an empty array, the form
    /// Foundation gives a dictionary with non-string keys. What this pins is
    /// that shape: a map keyed by anything else would throw on it.
    @Test func decodesTheEmptyLeafColorOverridesTheRealVersionThreeFileWrites() throws {
        let snapshot = try fixture("session-v3-real")
        let window = try #require(snapshot.windows.first)

        for tab in window.tabs {
            #expect(tab.leafColorOverrides.isEmpty)
            #expect(tab.colorOverride == nil)
        }
    }

    /// The version backup montty wrote before upgrading the file above. It
    /// predates `leafColorOverrides` and omits the key entirely, which is the
    /// case a synthetic fixture missed once before.
    @Test func migratesTheRealVersionTwoFileThatPredatesLeafColorOverrides() throws {
        let snapshot = try fixture("session-v2-real")

        #expect(snapshot.version == 2)
        let window = try #require(snapshot.windows.first)
        #expect(window.tabs.count == 3)
        #expect(window.tabs.allSatisfy { $0.leafColorOverrides.isEmpty })
        #expect(window.tabs.allSatisfy { !$0.leafDirectories.isEmpty })

        let (first, second) = try branchLeaves(window.tabs[0])
        #expect(first.id != second.id)
        #expect(window.tabs[0].focusedLeafID == first.id)
    }
}
