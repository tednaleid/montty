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

    /// Resolve the pane tint, returning a worktree gradient when applicable.
    /// Priority: tab override (always solid) > worktree gradient > solid repo color > nil.
    static func resolvedPaneTint(
        tabColorOverride: TabColor?,
        surfaceDirectory: String?,
        repoColorOverrides: [String: TabColor]
    ) -> PaneTint? {
        if let tabColorOverride {
            return PaneTint(primary: tabColorOverride, secondary: nil)
        }
        guard let dir = surfaceDirectory, let info = GitInfo.from(path: dir) else {
            return nil
        }
        guard let primary = colorForGitInfo(info, overrides: repoColorOverrides) else {
            return nil
        }
        guard info.worktreeName != nil else {
            return PaneTint(primary: primary, secondary: nil)
        }
        // Worktree -> derive a parent-repo color for the gradient's secondary stop.
        let parentInfo = GitInfo(
            repoName: info.repoName,
            branchName: nil,
            worktreeName: nil,
            repoPath: info.repoPath
        )
        let secondary = colorForGitInfo(parentInfo, overrides: repoColorOverrides) ?? primary
        return PaneTint(primary: primary, secondary: secondary)
    }
}

/// Two-color tint for a pane. When `secondary` is non-nil, render as a
/// LinearGradient (secondary on the leading edge, primary on trailing) to signal
/// that the pane is in a worktree of a parent repo. When nil, render solid.
struct PaneTint: Equatable {
    /// The worktree's color (or the only color when not in a worktree).
    let primary: TabColor
    /// The parent repo's color, only set when this pane is in a linked worktree.
    let secondary: TabColor?

    var isGradient: Bool { secondary != nil }
}
