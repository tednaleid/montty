import Foundation

extension TabColor {
    /// Derive a preset color from git repo identity.
    /// Same repo+worktree always produces the same color.
    /// Returns nil if not in a git repo (no tinting).
    static func colorForGitInfo(_ gitInfo: GitInfo?) -> PresetColor? {
        guard let gitInfo else { return nil }
        let identity = gitInfo.repoPath + (gitInfo.worktreeName ?? "")
        let hash = identity.utf8.reduce(UInt64(0)) { ($0 &+ UInt64($1)) &* 31 }
        // Gray is reserved for "no git repo" -- exclude it from the hash palette
        let colors = PresetColor.allCases.filter { $0 != .gray }
        return colors[Int(hash % UInt64(colors.count))]
    }

    /// Derive a preset color from a directory path via its git repo.
    /// Returns nil if not in a git repo.
    static func colorForDirectory(_ dir: String?) -> PresetColor? {
        guard let dir else { return nil }
        return colorForGitInfo(GitInfo.from(path: dir))
    }
}
