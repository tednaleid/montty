import Foundation

struct GitInfo: Equatable {
    let repoName: String        // basename of repo root
    let branchName: String?     // current branch, nil if detached HEAD
    let worktreeName: String?   // non-nil if in a linked worktree
    let repoPath: String        // absolute path to repo root

    /// Derive git info from a working directory path using pure filesystem reads.
    /// Returns nil if the path is not inside a git repository.
    static func from(path: String) -> GitInfo? {
        let fileManager = FileManager.default
        var current = path

        // Walk up from path looking for .git (file or directory)
        while current != "/" {
            let gitPath = (current as NSString).appendingPathComponent(".git")
            var isDir: ObjCBool = false

            guard fileManager.fileExists(atPath: gitPath, isDirectory: &isDir) else {
                current = (current as NSString).deletingLastPathComponent
                continue
            }

            if isDir.boolValue {
                // .git is a directory -- this is the main repo root
                let branch = readBranch(
                    headPath: (gitPath as NSString).appendingPathComponent("HEAD")
                )
                return GitInfo(
                    repoName: (current as NSString).lastPathComponent,
                    branchName: branch,
                    worktreeName: nil,
                    repoPath: current
                )
            } else {
                // .git is a file -- linked worktree or submodule
                return parseGitFile(gitFilePath: gitPath, currentRoot: current)
            }
        }

        return nil
    }

    /// Read branch name from a .git/HEAD file.
    /// Returns the branch name, or nil for detached HEAD.
    private static func readBranch(headPath: String) -> String? {
        guard let contents = try? String(contentsOfFile: headPath, encoding: .utf8) else {
            return nil
        }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        let refPrefix = "ref: refs/heads/"
        if trimmed.hasPrefix(refPrefix) {
            return String(trimmed.dropFirst(refPrefix.count))
        }
        // Raw SHA or other format -- detached HEAD
        return nil
    }

    /// Parse a .git file (worktree or submodule) to extract repo info.
    /// Worktree format: "gitdir: /path/to/main-repo/.git/worktrees/wt-name"
    /// Submodule format: "gitdir: /path/to/parent-repo/.git/modules/sub-name"
    private static func parseGitFile(
        gitFilePath: String, currentRoot: String
    ) -> GitInfo? {
        guard let contents = try? String(contentsOfFile: gitFilePath, encoding: .utf8) else {
            return nil
        }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "gitdir: "
        guard trimmed.hasPrefix(prefix) else { return nil }
        var gitDir = String(trimmed.dropFirst(prefix.count))

        // Resolve relative paths (e.g. "../.git/modules/ghostty")
        if !gitDir.hasPrefix("/") {
            let base = (gitFilePath as NSString).deletingLastPathComponent
            gitDir = ((base as NSString).appendingPathComponent(gitDir) as NSString)
                .standardizingPath
        }

        let parentDir = (gitDir as NSString).deletingLastPathComponent
        let parentName = (parentDir as NSString).lastPathComponent

        if parentName == "worktrees" {
            // Linked worktree: .git/worktrees/<wt-name>
            let worktreeName = (gitDir as NSString).lastPathComponent
            let mainGitDir = (parentDir as NSString).deletingLastPathComponent
            let mainRepoPath = (mainGitDir as NSString).deletingLastPathComponent
            let headPath = (gitDir as NSString).appendingPathComponent("HEAD")
            let branch = readBranch(headPath: headPath)
            return GitInfo(
                repoName: (mainRepoPath as NSString).lastPathComponent,
                branchName: branch,
                worktreeName: worktreeName,
                repoPath: mainRepoPath
            )
        } else if parentName == "modules" {
            // Submodule: .git/modules/<sub-name>
            // Use parent repo's identity so submodules get the same color
            let mainGitDir = (parentDir as NSString).deletingLastPathComponent
            let parentRepoPath = (mainGitDir as NSString).deletingLastPathComponent
            let parentHeadPath = (mainGitDir as NSString).appendingPathComponent("HEAD")
            let branch = readBranch(headPath: parentHeadPath)
            return GitInfo(
                repoName: (parentRepoPath as NSString).lastPathComponent,
                branchName: branch,
                worktreeName: nil,
                repoPath: parentRepoPath
            )
        }

        return nil
    }
}
