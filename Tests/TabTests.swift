import Foundation
import Testing

struct TabTests {
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

    @Test func displayNameEmptyWhenBothEmpty() {
        let tab = Tab(name: "", autoName: "")
        #expect(tab.displayName == "")
    }

    @Test func surfaceIDIsAssigned() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        #expect(tab.focusedSurfaceID == surfaceID)
    }

    @Test func splitRootStartsAsLeaf() {
        let tab = Tab()
        guard case .leaf = tab.splitRoot else {
            Issue.record("Expected leaf as initial splitRoot")
            return
        }
        #expect(tab.focusedLeafID != nil)
    }

    @Test func allSurfaceIDsReturnsOne() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        #expect(tab.allSurfaceIDs == [surfaceID])
    }

    // MARK: - Focused surface ID edge cases

    @Test func focusedSurfaceIDFallsBackWhenLeafIDMissing() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        // Set focusedLeafID to a UUID that doesn't exist in the tree
        tab.focusedLeafID = UUID()
        // Should fall back to the first leaf's surfaceID
        #expect(tab.focusedSurfaceID == surfaceID)
    }

    @Test func focusedSurfaceIDFallsBackWhenLeafIDNil() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        tab.focusedLeafID = nil
        #expect(tab.focusedSurfaceID == surfaceID)
    }

    // MARK: - Effective color

    @Test func effectiveColorDerivesFromGitRepoWhenAuto() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        // Use a path that's actually in a git repo (this project)
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().path
        tab.surfaceDirectories[surfaceID] = repoPath
        let color = tab.effectiveColor()
        // Should derive a color from the git repo, not gray
        #expect(color != .gray)
        // Should be deterministic
        #expect(color == tab.effectiveColor())
    }

    @Test func effectiveColorUseFocusedSurfaceDirectory() {
        // Two surfaces: one in a git repo, one not. Color should follow focus.
        let surfaceA = UUID()
        let surfaceB = UUID()
        let leafA = SurfaceLeaf(surfaceID: surfaceA)
        let leafB = SurfaceLeaf(surfaceID: surfaceB)
        let tab = Tab()
        tab.splitRoot = .split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(leafA),
            second: .leaf(leafB)
        ))
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().path
        tab.surfaceDirectories[surfaceA] = repoPath
        tab.surfaceDirectories[surfaceB] = "/tmp"

        // Focus surface A (git repo) -- should get a real color
        tab.focusedLeafID = leafA.id
        let colorA = tab.effectiveColor()
        #expect(colorA != .gray)

        // Focus surface B (non-git) -- should get gray
        tab.focusedLeafID = leafB.id
        #expect(tab.effectiveColor() == .gray)
    }

    @Test func effectiveColorReturnsGrayForNonGitDirectory() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        tab.surfaceDirectories[surfaceID] = "/tmp"
        #expect(tab.effectiveColor() == .gray)
    }

    @Test func effectiveColorReturnsGrayWhenNoDirectory() {
        let tab = Tab()
        #expect(tab.effectiveColor() == .gray)
    }

    @Test func effectiveColorRespectsOverride() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().path
        tab.surfaceDirectories[surfaceID] = repoPath

        let defaultColor = tab.effectiveColor()
        #expect(defaultColor != .gray)

        // Override to a different color
        let overrideColor: TabColor = (defaultColor == .magenta) ? .blue : .magenta
        let identity = TabColor.repoIdentity(for: repoPath)!
        let overrides = [identity: overrideColor]
        #expect(tab.effectiveColor(overrides: overrides) == overrideColor)
    }

    @Test func tabColorOverrideBeatsRepoOverride() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().path
        tab.surfaceDirectories[surfaceID] = repoPath

        // Set tab-level override
        tab.colorOverride = .cyan

        // Tab override should beat both hashed color and repo override
        #expect(tab.effectiveColor() == .cyan)
        let identity = TabColor.repoIdentity(for: repoPath)!
        let repoOverrides = [identity: TabColor.magenta]
        #expect(tab.effectiveColor(overrides: repoOverrides) == .cyan)
    }

    // MARK: - Claude waiting-state safety nets

    @Test func titleChangeClearsWaitingState() {
        let surfaceID = UUID()
        let monttyID = "mid-1"
        let tab = Tab(surfaceID: surfaceID)
        tab.surfaceToMonttyID[surfaceID] = monttyID
        tab.claudeStates[monttyID] = .waiting
        tab.claudeWaitingSince[monttyID] = Date()

        let changed = tab.clearWaitingOnTitleChange(for: surfaceID)

        #expect(changed == true)
        #expect(tab.claudeStates[monttyID] == .working)
        #expect(tab.claudeWaitingSince[monttyID] == nil)
    }

    @Test func titleChangeDoesNotDowngradeIdle() {
        let surfaceID = UUID()
        let monttyID = "mid-1"
        let tab = Tab(surfaceID: surfaceID)
        tab.surfaceToMonttyID[surfaceID] = monttyID
        tab.claudeStates[monttyID] = .idle

        let changed = tab.clearWaitingOnTitleChange(for: surfaceID)

        #expect(changed == false)
        #expect(tab.claudeStates[monttyID] == .idle)
    }

    @Test func titleChangeDoesNotUpgradeWorking() {
        let surfaceID = UUID()
        let monttyID = "mid-1"
        let tab = Tab(surfaceID: surfaceID)
        tab.surfaceToMonttyID[surfaceID] = monttyID
        tab.claudeStates[monttyID] = .working

        let changed = tab.clearWaitingOnTitleChange(for: surfaceID)

        #expect(changed == false)
        #expect(tab.claudeStates[monttyID] == .working)
    }

    @Test func titleChangeNoopForUnknownSurface() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        // No surfaceToMonttyID mapping, no claudeStates entry
        let changed = tab.clearWaitingOnTitleChange(for: surfaceID)
        #expect(changed == false)
    }

    @Test func sweepClearsWaitingOlderThanThreshold() {
        let monttyID = "mid-1"
        let tab = Tab()
        tab.claudeStates[monttyID] = .waiting
        let now = Date()
        tab.claudeWaitingSince[monttyID] = now.addingTimeInterval(-120) // 2 minutes ago

        let transitioned = tab.sweepStaleWaiting(threshold: 60, now: now)

        #expect(transitioned == [monttyID])
        #expect(tab.claudeStates[monttyID] == .idle)
        #expect(tab.claudeWaitingSince[monttyID] == nil)
    }

    @Test func sweepLeavesRecentWaiting() {
        let monttyID = "mid-1"
        let tab = Tab()
        tab.claudeStates[monttyID] = .waiting
        let now = Date()
        tab.claudeWaitingSince[monttyID] = now.addingTimeInterval(-30) // 30s ago

        let transitioned = tab.sweepStaleWaiting(threshold: 60, now: now)

        #expect(transitioned.isEmpty)
        #expect(tab.claudeStates[monttyID] == .waiting)
        #expect(tab.claudeWaitingSince[monttyID] != nil)
    }

    @Test func sweepIgnoresNonWaitingSurfaces() {
        let monttyID = "mid-1"
        let tab = Tab()
        tab.claudeStates[monttyID] = .working
        let now = Date()
        // Stale waitingSince but state is .working (shouldn't happen, but safe)
        tab.claudeWaitingSince[monttyID] = now.addingTimeInterval(-120)

        let transitioned = tab.sweepStaleWaiting(threshold: 60, now: now)

        #expect(transitioned.isEmpty)
        #expect(tab.claudeStates[monttyID] == .working)
    }

    @Test func sweepHandlesMultipleSurfaces() {
        let tab = Tab()
        let now = Date()
        tab.claudeStates["a"] = .waiting
        tab.claudeWaitingSince["a"] = now.addingTimeInterval(-120)  // stale
        tab.claudeStates["b"] = .waiting
        tab.claudeWaitingSince["b"] = now.addingTimeInterval(-10)   // fresh
        tab.claudeStates["c"] = .working                             // not waiting

        let transitioned = tab.sweepStaleWaiting(threshold: 60, now: now)

        #expect(Set(transitioned) == Set(["a"]))
        #expect(tab.claudeStates["a"] == .idle)
        #expect(tab.claudeStates["b"] == .waiting)
        #expect(tab.claudeStates["c"] == .working)
    }

    @Test func tabColorOverrideNilFallsThrough() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        let repoPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().path
        tab.surfaceDirectories[surfaceID] = repoPath

        tab.colorOverride = nil
        // Should use the git-hashed color, not gray
        #expect(tab.effectiveColor() != .gray)
    }
}
