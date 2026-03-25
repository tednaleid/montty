import Foundation
import Testing
@testable import montty_unit

struct TabInfoTests {
    /// Create TabProperties with a focused surface in the given directory.
    private func propsWithDir(
        _ dir: String, name: String = "", autoName: String = "zsh"
    ) -> TabProperties {
        let leaf = SurfaceLeaf()
        return TabProperties(
            name: name, autoName: autoName,
            splitRoot: .leaf(leaf), focusedLeafID: leaf.id,
            surfaceDirectories: [leaf.surfaceID: dir]
        )
    }

    /// Create TabProperties with no directory.
    private func propsNoDir(
        name: String = "", autoName: String = "zsh",
        splitRoot: SplitNode? = nil, focusedLeafID: UUID? = nil
    ) -> TabProperties {
        let root = splitRoot ?? .leaf(SurfaceLeaf())
        return TabProperties(
            name: name, autoName: autoName,
            splitRoot: root, focusedLeafID: focusedLeafID
        )
    }

    private func twoLeaves() -> SplitNode {
        .split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(SurfaceLeaf()),
            second: .leaf(SurfaceLeaf())
        ))
    }

    private func threeLeaves() -> SplitNode {
        .split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(SurfaceLeaf()),
            second: .split(SplitBranch(
                orientation: .vertical,
                first: .leaf(SurfaceLeaf()),
                second: .leaf(SurfaceLeaf())
            ))
        ))
    }

    // MARK: - Display name

    @Test func tabInfoDisplaysUserName() {
        let props = propsNoDir(name: "My Server")
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "My Server")
    }

    @Test func tabInfoFallsBackToAutoName() {
        let props = propsNoDir(autoName: "vim main.swift")
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "vim main.swift")
    }

    @Test func tabInfoFallsBackToTerminal() {
        let props = propsNoDir(name: "", autoName: "")
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "Terminal")
    }

    @Test func tabInfoShowsShortDirName() {
        let props = propsWithDir("/Users/ted/projects/montty")
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "montty/")
    }

    @Test func tabInfoShowsRootDirWithoutPrefix() {
        let props = propsWithDir("/tmp")
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "/tmp")
    }

    @Test func tabInfoShowsHomeDirAsTilde() {
        let home = NSHomeDirectory()
        let props = propsWithDir(home)
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "~")
    }

    @Test func tabInfoShowsDirectChildOfHomeWithTilde() {
        let home = NSHomeDirectory()
        let props = propsWithDir(home + "/Documents")
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "~/Documents")
    }

    @Test func tabInfoShowsNestedHomeDirWithEllipsis() {
        let home = NSHomeDirectory()
        let props = propsWithDir(home + "/Documents/projects/montty")
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "montty/")
    }

    @Test func tabInfoShowsRootAsSlash() {
        let props = propsWithDir("/")
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "/")
    }

    // MARK: - Directory

    @Test func tabInfoExtractsDirectoryName() {
        let props = propsWithDir("/Users/ted/projects/montty")
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.directoryName == "montty")
        #expect(info.workingDirectory == "/Users/ted/projects/montty")
    }

    @Test func tabInfoNilDirectoryWhenMissing() {
        let props = propsNoDir()
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.directoryName == nil)
        #expect(info.workingDirectory == nil)
    }

    // MARK: - Surface directories

    @Test func tabInfoUsesFocusedSurfaceDirectory() {
        // Focused leaf's directory is used for the display name
        let props = propsWithDir("/Users/ted/projects/montty")
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.workingDirectory == "/Users/ted/projects/montty")
        #expect(info.directoryName == "montty")
    }

    // MARK: - Git info integration

    @Test func tabInfoIncludesGitInfo() {
        let mockGit = GitInfo(
            repoName: "montty",
            branchName: "main",
            worktreeName: nil,
            repoPath: "/Users/ted/projects/montty"
        )
        let props = propsWithDir("/Users/ted/projects/montty/Sources")
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in mockGit })
        #expect(info.gitInfo == mockGit)
    }

    @Test func tabInfoNilGitOutsideRepo() {
        let props = propsWithDir("/tmp")
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.gitInfo == nil)
    }

    // MARK: - Split count

    @Test func tabInfoSplitCountSingle() {
        let props = propsNoDir()
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.splitCount == 1)
    }

    @Test func tabInfoSplitCountTwo() {
        let props = propsNoDir(splitRoot: twoLeaves())
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.splitCount == 2)
    }

    @Test func tabInfoSplitCountNested() {
        let props = propsNoDir(splitRoot: threeLeaves())
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.splitCount == 3)
    }

    // MARK: - Claude Code detection (stub)

    @Test func tabInfoDetectsClaudeCode() {
        let props = propsNoDir(autoName: "✳ fixing the BCI toggle")
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.claudeCode?.sessionName == "fixing the BCI toggle")
        #expect(info.claudeCode?.state == .unknown)
    }

    @Test func tabInfoNoClaudeCodeForNormalTitle() {
        let props = propsNoDir()
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.claudeCode == nil)
    }
}
