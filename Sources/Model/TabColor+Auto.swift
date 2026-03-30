import Foundation

extension TabColor {
    /// Derive a color from git repo identity, checking overrides first.
    /// Same repo+worktree always produces the same color.
    /// Returns nil if not in a git repo (no tinting).
    static func colorForGitInfo(
        _ gitInfo: GitInfo?,
        overrides: [String: TabColor] = [:]
    ) -> TabColor? {
        guard let gitInfo else { return nil }
        let identity = gitInfo.repoPath + (gitInfo.worktreeName ?? "")
        if let override = overrides[identity] { return override }
        let hash = identity.utf8.reduce(UInt64(0)) { ($0 &+ UInt64($1)) &* 31 }
        // Gray is reserved for "no git repo" -- exclude it from the hash palette
        let colors = TabColor.allCases.filter { $0 != .gray }
        return colors[Int(hash % UInt64(colors.count))]
    }

    /// Derive a color from a directory path via its git repo.
    /// Returns nil if not in a git repo.
    static func colorForWorktree(
        _ dir: String?,
        overrides: [String: TabColor] = [:]
    ) -> TabColor? {
        guard let dir else { return nil }
        return colorForGitInfo(GitInfo.from(path: dir), overrides: overrides)
    }

    /// Resolve the display color for a minimap pane.
    /// Tab-level override wins over per-surface directory color.
    static func resolvedPaneColor(
        tabColorOverride: TabColor?,
        surfaceDirectory: String?,
        repoColorOverrides: [String: TabColor]
    ) -> TabColor? {
        if let tabColorOverride { return tabColorOverride }
        return colorForWorktree(surfaceDirectory, overrides: repoColorOverrides)
    }

    /// The repo identity string for a directory, used as the key in overrides.
    /// Returns nil if not in a git repo.
    static func repoIdentity(for dir: String?) -> String? {
        guard let dir, let gitInfo = GitInfo.from(path: dir) else { return nil }
        return gitInfo.repoPath + (gitInfo.worktreeName ?? "")
    }
}
