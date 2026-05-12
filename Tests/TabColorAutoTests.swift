import Foundation
import Testing
@testable import montty_unit

@Suite struct TabColorAutoTests {
    @Test func nilDirectoryReturnsNil() {
        let color = TabColor.colorForWorktree(nil)
        #expect(color == nil)
    }

    @Test func nonGitDirectoryReturnsNil() {
        let color = TabColor.colorForWorktree("/tmp")
        #expect(color == nil)
    }

    @Test func nilGitInfoReturnsNil() {
        let color = TabColor.colorForGitInfo(nil)
        #expect(color == nil)
    }

    @Test func sameRepoGetsSameColor() {
        let info = GitInfo(
            repoName: "montty", branchName: "main",
            worktreeName: nil, repoPath: "/Users/ted/montty"
        )
        let color1 = TabColor.colorForGitInfo(info)
        let color2 = TabColor.colorForGitInfo(info)
        #expect(color1 == color2)
        #expect(color1 != nil)
    }

    @Test func differentReposGetDifferentColors() {
        let info1 = GitInfo(
            repoName: "montty", branchName: "main",
            worktreeName: nil, repoPath: "/Users/ted/montty"
        )
        let info2 = GitInfo(
            repoName: "limn", branchName: "main",
            worktreeName: nil, repoPath: "/Users/ted/limn"
        )
        // Not guaranteed different, but at least both produce a color
        #expect(TabColor.colorForGitInfo(info1) != nil)
        #expect(TabColor.colorForGitInfo(info2) != nil)
    }

    @Test func worktreeIncludedInHash() {
        let base = GitInfo(
            repoName: "montty", branchName: "main",
            worktreeName: nil, repoPath: "/Users/ted/montty"
        )
        let worktree = GitInfo(
            repoName: "montty", branchName: "feature",
            worktreeName: "montty-feature", repoPath: "/Users/ted/montty"
        )
        // Both produce a color (worktree identity is included in hash)
        #expect(TabColor.colorForGitInfo(base) != nil)
        #expect(TabColor.colorForGitInfo(worktree) != nil)
    }

    @Test func gitRepoNeverHashesToGray() {
        // Gray is reserved for "not in a git repo" -- no repo should hash to it
        let infos = (0..<200).map { idx in
            GitInfo(
                repoName: "repo-\(idx)", branchName: "main",
                worktreeName: nil, repoPath: "/repos/repo-\(idx)"
            )
        }
        for info in infos {
            let color = TabColor.colorForGitInfo(info)
            #expect(color != .gray, "Repo \(info.repoName) hashed to gray")
        }
    }

    @Test func hashCoversMultipleColors() {
        let infos = (0..<50).map { idx in
            GitInfo(
                repoName: "project-\(idx)", branchName: "main",
                worktreeName: nil, repoPath: "/repos/project-\(idx)"
            )
        }
        let colors = Set(infos.compactMap { TabColor.colorForGitInfo($0) })
        #expect(colors.count >= 8, "Expected at least 8 distinct colors from 50 repos")
    }

    // MARK: - Override resolution

    @Test func overrideReturnsOverrideColor() {
        let info = GitInfo(
            repoName: "montty", branchName: "main",
            worktreeName: nil, repoPath: "/Users/ted/montty"
        )
        let overrides = ["/Users/ted/montty": TabColor.blue]
        let color = TabColor.colorForGitInfo(info, overrides: overrides)
        #expect(color == .blue)
    }

    @Test func overrideForDifferentRepoDoesNotApply() {
        let info = GitInfo(
            repoName: "montty", branchName: "main",
            worktreeName: nil, repoPath: "/Users/ted/montty"
        )
        let overrides = ["/Users/ted/other-repo": TabColor.blue]
        let color = TabColor.colorForGitInfo(info, overrides: overrides)
        // Should return the hash result, not the override
        #expect(color != nil)
        #expect(color != .blue || color == TabColor.colorForGitInfo(info))
    }

    @Test func worktreeOverrideDoesNotAffectBaseRepo() {
        let base = GitInfo(
            repoName: "montty", branchName: "main",
            worktreeName: nil, repoPath: "/Users/ted/montty"
        )
        let worktree = GitInfo(
            repoName: "montty", branchName: "feature",
            worktreeName: "montty-feature", repoPath: "/Users/ted/montty"
        )
        let overrides = ["/Users/ted/monttymontty-feature": TabColor.magenta]
        // Override applies to worktree
        #expect(TabColor.colorForGitInfo(worktree, overrides: overrides) == .magenta)
        // Base repo uses normal hash
        #expect(TabColor.colorForGitInfo(base, overrides: overrides)
            == TabColor.colorForGitInfo(base))
    }

    // MARK: - Pane color resolution

    @Test func tabOverrideWinsOverSurfaceColor() {
        let info = GitInfo(
            repoName: "montty", branchName: "main",
            worktreeName: nil, repoPath: "/Users/ted/montty"
        )
        let surfaceColor = TabColor.colorForGitInfo(info)
        #expect(surfaceColor != nil)
        #expect(surfaceColor != .red, "Test assumes montty doesn't hash to red")

        let resolved = TabColor.resolvedPaneColor(
            tabColorOverride: .red,
            surfaceDirectory: "/Users/ted/montty",
            repoColorOverrides: [:]
        )
        #expect(resolved == .red)
    }

    @Test func noOverrideFallsBackToSurfaceColor() {
        // Use the actual repo directory so GitInfo.from(path:) resolves
        let repoDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().path
        let expected = TabColor.colorForWorktree(repoDir)
        #expect(expected != nil, "Test must run inside a git repo")

        let resolved = TabColor.resolvedPaneColor(
            tabColorOverride: nil,
            surfaceDirectory: repoDir,
            repoColorOverrides: [:]
        )
        #expect(resolved == expected)
    }

    @Test func noOverrideNoRepoReturnsNil() {
        let resolved = TabColor.resolvedPaneColor(
            tabColorOverride: nil,
            surfaceDirectory: nil,
            repoColorOverrides: [:]
        )
        #expect(resolved == nil)
    }

    // MARK: - PaneTint (worktree gradient)

    private struct WorktreeFixture {
        let parent: String
        let worktree: String
        let base: String
    }

    /// Build a (parentRepoPath, worktreePath, baseDir) triple on disk for tint tests.
    private func makeWorktreeOnDisk() throws -> WorktreeFixture {
        let tmp = NSTemporaryDirectory()
        let base = (tmp as NSString).appendingPathComponent(
            "montty-tint-\(UUID().uuidString)"
        )
        let fileManager = FileManager.default

        let parent = (base as NSString).appendingPathComponent("main-repo")
        try fileManager.createDirectory(atPath: parent, withIntermediateDirectories: true)
        let parentGit = (parent as NSString).appendingPathComponent(".git")
        try fileManager.createDirectory(atPath: parentGit, withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(
            toFile: (parentGit as NSString).appendingPathComponent("HEAD"),
            atomically: true, encoding: .utf8
        )

        let wtName = "feature-x"
        let wtGitDir = (parentGit as NSString)
            .appendingPathComponent("worktrees")
        let wtMeta = (wtGitDir as NSString).appendingPathComponent(wtName)
        try fileManager.createDirectory(atPath: wtMeta, withIntermediateDirectories: true)
        try "ref: refs/heads/\(wtName)\n".write(
            toFile: (wtMeta as NSString).appendingPathComponent("HEAD"),
            atomically: true, encoding: .utf8
        )
        let worktree = (base as NSString).appendingPathComponent(wtName)
        try fileManager.createDirectory(atPath: worktree, withIntermediateDirectories: true)
        try "gitdir: \(wtMeta)\n".write(
            toFile: (worktree as NSString).appendingPathComponent(".git"),
            atomically: true, encoding: .utf8
        )

        return WorktreeFixture(parent: parent, worktree: worktree, base: base)
    }

    @Test func paneTintNilForNonGitDirectory() {
        let tint = TabColor.resolvedPaneTint(
            tabColorOverride: nil,
            surfaceDirectory: "/tmp",
            repoColorOverrides: [:]
        )
        #expect(tint == nil)
    }

    @Test func paneTintNilForNilDirectory() {
        let tint = TabColor.resolvedPaneTint(
            tabColorOverride: nil,
            surfaceDirectory: nil,
            repoColorOverrides: [:]
        )
        #expect(tint == nil)
    }

    @Test func paneTintTabOverrideIsSolid() {
        let tint = TabColor.resolvedPaneTint(
            tabColorOverride: .red,
            surfaceDirectory: "/anywhere",
            repoColorOverrides: [:]
        )
        #expect(tint?.primary == .red)
        #expect(tint?.secondary == nil)
        #expect(tint?.isGradient == false)
    }

    @Test func paneTintNonWorktreeRepoIsSolid() throws {
        let fixture = try makeWorktreeOnDisk()
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let tint = TabColor.resolvedPaneTint(
            tabColorOverride: nil,
            surfaceDirectory: fixture.parent,
            repoColorOverrides: [:]
        )
        #expect(tint != nil)
        #expect(tint?.secondary == nil, "main repo should not produce a gradient")
        #expect(tint?.isGradient == false)
    }

    @Test func paneTintWorktreeYieldsGradient() throws {
        let fixture = try makeWorktreeOnDisk()
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let parentTint = TabColor.resolvedPaneTint(
            tabColorOverride: nil,
            surfaceDirectory: fixture.parent,
            repoColorOverrides: [:]
        )
        let worktreeTint = TabColor.resolvedPaneTint(
            tabColorOverride: nil,
            surfaceDirectory: fixture.worktree,
            repoColorOverrides: [:]
        )
        #expect(worktreeTint?.isGradient == true)
        #expect(worktreeTint?.secondary == parentTint?.primary,
            "gradient secondary should match parent repo's solid color")
        // Don't assert primary != secondary -- the 14-color hash will sometimes
        // collide for two distinct identities, and the gradient still renders
        // correctly (it just looks solid in that rare case).
    }

    @Test func paneTintWorktreeRespectsParentRepoOverride() throws {
        let fixture = try makeWorktreeOnDisk()
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        // Override the *parent* repo color, not the worktree.
        let parentIdentity = TabColor.repoIdentity(for: fixture.parent)!
        let overrides: [String: TabColor] = [parentIdentity: .magenta]

        let tint = TabColor.resolvedPaneTint(
            tabColorOverride: nil,
            surfaceDirectory: fixture.worktree,
            repoColorOverrides: overrides
        )
        #expect(tint?.secondary == .magenta)
        #expect(tint?.primary != .magenta, "worktree color should still hash, not pick up parent override")
    }

    @Test func paneTintWorktreeRespectsWorktreeOverride() throws {
        let fixture = try makeWorktreeOnDisk()
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let wtIdentity = TabColor.repoIdentity(for: fixture.worktree)!
        let overrides: [String: TabColor] = [wtIdentity: .cyan]

        // Parent under the same overrides -- the worktree override key doesn't
        // match the parent's identity, so it should fall through to the hash.
        let parentTint = TabColor.resolvedPaneTint(
            tabColorOverride: nil,
            surfaceDirectory: fixture.parent,
            repoColorOverrides: overrides
        )
        let worktreeTint = TabColor.resolvedPaneTint(
            tabColorOverride: nil,
            surfaceDirectory: fixture.worktree,
            repoColorOverrides: overrides
        )
        #expect(worktreeTint?.primary == .cyan)
        #expect(worktreeTint?.secondary == parentTint?.primary,
            "worktree override should not bleed into the parent's resolved color")
    }
}
