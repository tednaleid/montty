import Foundation
import Testing
@testable import montty_unit

struct GitInfoTests {
    /// Create a temp directory with a real .git structure for testing.
    private func makeGitRepo(
        name: String = "test-repo",
        branch: String = "main"
    ) throws -> String {
        let tmp = NSTemporaryDirectory()
        let repoPath = (tmp as NSString).appendingPathComponent(
            "montty-test-\(UUID().uuidString)/\(name)"
        )
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: repoPath, withIntermediateDirectories: true)

        // Create .git directory with HEAD file
        let gitDir = (repoPath as NSString).appendingPathComponent(".git")
        try fileManager.createDirectory(atPath: gitDir, withIntermediateDirectories: true)
        let headPath = (gitDir as NSString).appendingPathComponent("HEAD")
        try "ref: refs/heads/\(branch)\n".write(
            toFile: headPath, atomically: true, encoding: .utf8
        )
        return repoPath
    }

    /// Create a detached HEAD repo.
    private func makeDetachedRepo(name: String = "detached-repo") throws -> String {
        let tmp = NSTemporaryDirectory()
        let repoPath = (tmp as NSString).appendingPathComponent(
            "montty-test-\(UUID().uuidString)/\(name)"
        )
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: repoPath, withIntermediateDirectories: true)

        let gitDir = (repoPath as NSString).appendingPathComponent(".git")
        try fileManager.createDirectory(atPath: gitDir, withIntermediateDirectories: true)
        let headPath = (gitDir as NSString).appendingPathComponent("HEAD")
        try "abc123def456789\n".write(
            toFile: headPath, atomically: true, encoding: .utf8
        )
        return repoPath
    }

    /// Create a linked worktree (`.git` is a file pointing to main repo).
    private func makeWorktree(
        mainRepoName: String = "main-repo",
        worktreeName: String = "feature-branch"
    ) throws -> (mainRepoPath: String, worktreePath: String) {
        let tmp = NSTemporaryDirectory()
        let base = (tmp as NSString).appendingPathComponent(
            "montty-test-\(UUID().uuidString)"
        )
        let fileManager = FileManager.default

        // Create main repo
        let mainRepoPath = (base as NSString).appendingPathComponent(mainRepoName)
        try fileManager.createDirectory(atPath: mainRepoPath, withIntermediateDirectories: true)
        let mainGitDir = (mainRepoPath as NSString).appendingPathComponent(".git")
        try fileManager.createDirectory(atPath: mainGitDir, withIntermediateDirectories: true)
        let mainHead = (mainGitDir as NSString).appendingPathComponent("HEAD")
        try "ref: refs/heads/main\n".write(
            toFile: mainHead, atomically: true, encoding: .utf8
        )

        // Create worktree directory structure inside main repo's .git
        let worktreesDir = (mainGitDir as NSString).appendingPathComponent("worktrees")
        let wtGitDir = (worktreesDir as NSString).appendingPathComponent(worktreeName)
        try fileManager.createDirectory(atPath: wtGitDir, withIntermediateDirectories: true)
        let wtHead = (wtGitDir as NSString).appendingPathComponent("HEAD")
        try "ref: refs/heads/\(worktreeName)\n".write(
            toFile: wtHead, atomically: true, encoding: .utf8
        )

        // Create the worktree directory with .git file
        let worktreePath = (base as NSString).appendingPathComponent(worktreeName)
        try fileManager.createDirectory(atPath: worktreePath, withIntermediateDirectories: true)
        let wtGitFile = (worktreePath as NSString).appendingPathComponent(".git")
        try "gitdir: \(wtGitDir)\n".write(
            toFile: wtGitFile, atomically: true, encoding: .utf8
        )

        return (mainRepoPath, worktreePath)
    }

    /// Create a submodule (`.git` is a file pointing to parent's `.git/modules/`).
    private func makeSubmodule(
        parentRepoName: String = "parent-repo",
        submoduleName: String = "child-module"
    ) throws -> (parentRepoPath: String, submodulePath: String) {
        let tmp = NSTemporaryDirectory()
        let base = (tmp as NSString).appendingPathComponent(
            "montty-test-\(UUID().uuidString)"
        )
        let fileManager = FileManager.default

        // Create parent repo
        let parentRepoPath = (base as NSString).appendingPathComponent(parentRepoName)
        try fileManager.createDirectory(atPath: parentRepoPath, withIntermediateDirectories: true)
        let parentGitDir = (parentRepoPath as NSString).appendingPathComponent(".git")
        try fileManager.createDirectory(atPath: parentGitDir, withIntermediateDirectories: true)
        let parentHead = (parentGitDir as NSString).appendingPathComponent("HEAD")
        try "ref: refs/heads/main\n".write(
            toFile: parentHead, atomically: true, encoding: .utf8
        )

        // Create .git/modules/<submodule> directory with HEAD
        let modulesDir = (parentGitDir as NSString).appendingPathComponent("modules")
        let moduleGitDir = (modulesDir as NSString).appendingPathComponent(submoduleName)
        try fileManager.createDirectory(atPath: moduleGitDir, withIntermediateDirectories: true)
        let moduleHead = (moduleGitDir as NSString).appendingPathComponent("HEAD")
        try "abc123def456789\n".write(
            toFile: moduleHead, atomically: true, encoding: .utf8
        )

        // Create the submodule directory with .git file
        let submodulePath = (parentRepoPath as NSString).appendingPathComponent(submoduleName)
        try fileManager.createDirectory(atPath: submodulePath, withIntermediateDirectories: true)
        let subGitFile = (submodulePath as NSString).appendingPathComponent(".git")
        try "gitdir: \(moduleGitDir)\n".write(
            toFile: subGitFile, atomically: true, encoding: .utf8
        )

        return (parentRepoPath, submodulePath)
    }

    private func cleanup(_ path: String) {
        // Find the montty-test-UUID parent to clean up the whole tree
        let components = path.split(separator: "/")
        if let testIdx = components.firstIndex(where: { $0.hasPrefix("montty-test-") }) {
            let cleanPath = "/" + components[...testIdx].joined(separator: "/")
            try? FileManager.default.removeItem(atPath: cleanPath)
        }
    }

    // MARK: - Tests

    @Test func gitInfoFromRepoRoot() throws {
        let repoPath = try makeGitRepo(name: "my-project", branch: "main")
        defer { cleanup(repoPath) }

        let info = GitInfo.from(path: repoPath)
        #expect(info != nil)
        #expect(info?.repoName == "my-project")
        #expect(info?.branchName == "main")
        #expect(info?.repoPath == repoPath)
        #expect(info?.worktreeName == nil)
    }

    @Test func gitInfoFromSubdirectory() throws {
        let repoPath = try makeGitRepo(name: "nested-project", branch: "develop")
        defer { cleanup(repoPath) }

        let subDir = (repoPath as NSString).appendingPathComponent("src/deep/nested")
        try FileManager.default.createDirectory(
            atPath: subDir, withIntermediateDirectories: true
        )

        let info = GitInfo.from(path: subDir)
        #expect(info != nil)
        #expect(info?.repoName == "nested-project")
        #expect(info?.branchName == "develop")
        #expect(info?.repoPath == repoPath)
    }

    @Test func gitInfoDetachedHead() throws {
        let repoPath = try makeDetachedRepo(name: "detached")
        defer { cleanup(repoPath) }

        let info = GitInfo.from(path: repoPath)
        #expect(info != nil)
        #expect(info?.repoName == "detached")
        #expect(info?.branchName == nil)
    }

    @Test func gitInfoReturnsNilOutsideRepo() {
        let info = GitInfo.from(path: NSTemporaryDirectory())
        #expect(info == nil)
    }

    @Test func gitInfoRepoName() throws {
        let repoPath = try makeGitRepo(name: "cool-app", branch: "main")
        defer { cleanup(repoPath) }

        let info = GitInfo.from(path: repoPath)
        #expect(info?.repoName == "cool-app")
    }

    @Test func gitInfoSubmoduleUsesParentRepo() throws {
        let (parentRepoPath, submodulePath) = try makeSubmodule(
            parentRepoName: "montty",
            submoduleName: "ghostty"
        )
        defer {
            cleanup(parentRepoPath)
        }

        let info = GitInfo.from(path: submodulePath)
        #expect(info != nil)
        // Submodule should use parent repo's identity for coloring
        #expect(info?.repoName == "montty")
        #expect(info?.repoPath == parentRepoPath)
        #expect(info?.worktreeName == nil)
    }

    @Test func gitInfoWorktree() throws {
        let (mainRepoPath, worktreePath) = try makeWorktree(
            mainRepoName: "my-project",
            worktreeName: "feature-xyz"
        )
        defer {
            cleanup(mainRepoPath)
            cleanup(worktreePath)
        }

        let info = GitInfo.from(path: worktreePath)
        #expect(info != nil)
        #expect(info?.repoName == "my-project")
        #expect(info?.branchName == "feature-xyz")
        #expect(info?.worktreeName == "feature-xyz")
        #expect(info?.repoPath == mainRepoPath)
    }
}
