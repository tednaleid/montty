import Foundation
import Testing
@testable import montty_unit

struct TabInfoTests {
    private func singleLeaf() -> SplitNode {
        .leaf(SurfaceLeaf())
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
        let props = TabProperties(
            name: "My Server",
            autoName: "zsh",
            workingDirectory: nil,
            splitRoot: singleLeaf(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "My Server")
    }

    @Test func tabInfoFallsBackToAutoName() {
        let props = TabProperties(
            name: "",
            autoName: "vim main.swift",
            workingDirectory: nil,
            splitRoot: singleLeaf(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "vim main.swift")
    }

    @Test func tabInfoFallsBackToTerminal() {
        let props = TabProperties(
            name: "",
            autoName: "",
            workingDirectory: nil,
            splitRoot: singleLeaf(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "Terminal")
    }

    @Test func tabInfoShowsShortDirName() {
        let props = TabProperties(
            name: "",
            autoName: "zsh",
            workingDirectory: "/Users/ted/projects/montty",
            splitRoot: singleLeaf(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "montty/")
    }

    @Test func tabInfoShowsRootDirWithoutPrefix() {
        let props = TabProperties(
            name: "",
            autoName: "zsh",
            workingDirectory: "/tmp",
            splitRoot: singleLeaf(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "/tmp")
    }

    @Test func tabInfoShowsHomeDirAsTilde() {
        let home = NSHomeDirectory()
        let props = TabProperties(
            name: "",
            autoName: "zsh",
            workingDirectory: home,
            splitRoot: singleLeaf(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "~")
    }

    @Test func tabInfoShowsDirectChildOfHomeWithTilde() {
        let home = NSHomeDirectory()
        let props = TabProperties(
            name: "",
            autoName: "zsh",
            workingDirectory: home + "/Documents",
            splitRoot: singleLeaf(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "~/Documents")
    }

    @Test func tabInfoShowsNestedHomeDirWithEllipsis() {
        let home = NSHomeDirectory()
        let props = TabProperties(
            name: "",
            autoName: "zsh",
            workingDirectory: home + "/Documents/projects/montty",
            splitRoot: singleLeaf(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "montty/")
    }

    @Test func tabInfoShowsRootAsSlash() {
        let props = TabProperties(
            name: "",
            autoName: "zsh",
            workingDirectory: "/",
            splitRoot: singleLeaf(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.displayName == "/")
    }

    // MARK: - Directory

    @Test func tabInfoExtractsDirectoryName() {
        let props = TabProperties(
            name: "",
            autoName: "zsh",
            workingDirectory: "/Users/ted/projects/montty",
            splitRoot: singleLeaf(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.directoryName == "montty")
        #expect(info.workingDirectory == "/Users/ted/projects/montty")
    }

    @Test func tabInfoNilDirectoryWhenMissing() {
        let props = TabProperties(
            name: "",
            autoName: "zsh",
            workingDirectory: nil,
            splitRoot: singleLeaf(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.directoryName == nil)
        #expect(info.workingDirectory == nil)
    }

    // MARK: - Surface directories

    @Test func tabInfoUsesFocusedSurfaceDirectory() {
        // Focused leaf's directory should win over tab-level workingDirectory
        let leaf = SurfaceLeaf()
        let props = TabProperties(
            name: "",
            autoName: "zsh",
            workingDirectory: "/Users/ted/old-dir",
            splitRoot: .leaf(leaf),
            focusedLeafID: leaf.id,
            surfaceDirectories: [leaf.surfaceID: "/Users/ted/projects/montty"]
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.workingDirectory == "/Users/ted/projects/montty")
        #expect(info.directoryName == "montty")
    }

    @Test func tabInfoFallsBackToWorkingDirectoryWhenNoSurfaceDir() {
        let leaf = SurfaceLeaf()
        let props = TabProperties(
            name: "",
            autoName: "zsh",
            workingDirectory: "/Users/ted/fallback",
            splitRoot: .leaf(leaf),
            focusedLeafID: leaf.id,
            surfaceDirectories: [:]
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.workingDirectory == "/Users/ted/fallback")
        #expect(info.directoryName == "fallback")
    }

    // MARK: - Git info integration

    @Test func tabInfoIncludesGitInfo() {
        let mockGit = GitInfo(
            repoName: "montty",
            branchName: "main",
            worktreeName: nil,
            repoPath: "/Users/ted/projects/montty"
        )
        let props = TabProperties(
            name: "",
            autoName: "zsh",
            workingDirectory: "/Users/ted/projects/montty/Sources",
            splitRoot: singleLeaf(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in mockGit })
        #expect(info.gitInfo == mockGit)
    }

    @Test func tabInfoNilGitOutsideRepo() {
        let props = TabProperties(
            name: "",
            autoName: "zsh",
            workingDirectory: "/tmp",
            splitRoot: singleLeaf(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.gitInfo == nil)
    }

    // MARK: - Split count

    @Test func tabInfoSplitCountSingle() {
        let props = TabProperties(
            name: "",
            autoName: "zsh",
            workingDirectory: nil,
            splitRoot: singleLeaf(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.splitCount == 1)
    }

    @Test func tabInfoSplitCountTwo() {
        let props = TabProperties(
            name: "",
            autoName: "zsh",
            workingDirectory: nil,
            splitRoot: twoLeaves(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.splitCount == 2)
    }

    @Test func tabInfoSplitCountNested() {
        let props = TabProperties(
            name: "",
            autoName: "zsh",
            workingDirectory: nil,
            splitRoot: threeLeaves(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.splitCount == 3)
    }

    // MARK: - Claude Code detection (stub)

    @Test func tabInfoDetectsClaudeCode() {
        let props = TabProperties(
            name: "",
            autoName: "✳ fixing the BCI toggle",
            workingDirectory: nil,
            splitRoot: singleLeaf(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.claudeCode?.sessionName == "fixing the BCI toggle")
        #expect(info.claudeCode?.state == .unknown)
    }

    @Test func tabInfoNoClaudeCodeForNormalTitle() {
        let props = TabProperties(
            name: "",
            autoName: "zsh",
            workingDirectory: nil,
            splitRoot: singleLeaf(),
            focusedLeafID: nil
        )
        let info = TabInfo.from(tab: props, gitInfoProvider: { _ in nil })
        #expect(info.claudeCode == nil)
    }
}
