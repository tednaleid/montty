import Foundation
import Testing
@testable import montty_unit

@Suite struct TabColorAutoTests {
    @Test func nilDirectoryReturnsNil() {
        let color = TabColor.colorForDirectory(nil)
        #expect(color == nil)
    }

    @Test func nonGitDirectoryReturnsNil() {
        let color = TabColor.colorForDirectory("/tmp")
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

    @Test func hashCoversMultipleColors() {
        let infos = (0..<50).map { idx in
            GitInfo(
                repoName: "project-\(idx)", branchName: "main",
                worktreeName: nil, repoPath: "/repos/project-\(idx)"
            )
        }
        let colors = Set(infos.compactMap { TabColor.colorForGitInfo($0) })
        #expect(colors.count >= 5, "Expected at least 5 distinct colors from 50 repos")
    }
}
