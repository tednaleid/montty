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
                // .git is a file -- this is a linked worktree
                // File contents: "gitdir: /path/to/main-repo/.git/worktrees/wt-name\n"
                return parseWorktree(gitFilePath: gitPath, worktreeRoot: current)
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

    /// Parse a worktree .git file to extract repo info.
    /// The .git file contains: "gitdir: /path/to/main-repo/.git/worktrees/wt-name"
    private static func parseWorktree(
        gitFilePath: String, worktreeRoot: String
    ) -> GitInfo? {
        guard let contents = try? String(contentsOfFile: gitFilePath, encoding: .utf8) else {
            return nil
        }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "gitdir: "
        guard trimmed.hasPrefix(prefix) else { return nil }
        let gitDir = String(trimmed.dropFirst(prefix.count))

        // gitDir looks like: /path/to/main-repo/.git/worktrees/wt-name
        // Walk up to find the main .git directory (parent of "worktrees")
        let worktreeName = (gitDir as NSString).lastPathComponent
        let worktreesDir = (gitDir as NSString).deletingLastPathComponent
        guard (worktreesDir as NSString).lastPathComponent == "worktrees" else {
            return nil
        }
        let mainGitDir = (worktreesDir as NSString).deletingLastPathComponent
        let mainRepoPath = (mainGitDir as NSString).deletingLastPathComponent

        // Read branch from the worktree's HEAD file
        let headPath = (gitDir as NSString).appendingPathComponent("HEAD")
        let branch = readBranch(headPath: headPath)

        return GitInfo(
            repoName: (mainRepoPath as NSString).lastPathComponent,
            branchName: branch,
            worktreeName: worktreeName,
            repoPath: mainRepoPath
        )
    }
}
