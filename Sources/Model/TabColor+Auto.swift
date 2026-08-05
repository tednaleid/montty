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

    /// The leading gradient stop for a repo identity. Hashed independently of
    /// the primary color, so two repos that collide on one color are unlikely to
    /// collide on both. Never returns the primary, so the pair is always visible
    /// as a gradient rather than a flat block.
    static func secondaryColor(for identity: String, excluding primary: TabColor) -> TabColor {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in identity.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        let colors = TabColor.allCases.filter { $0 != .gray && $0 != primary }
        return colors[Int(hash % UInt64(colors.count))]
    }

    /// Gradient stops for a git location. A repo gets its own two-color
    /// signature. A worktree carries its parent repo's signature on the leading
    /// edge and its own color on the trailing edge, so every worktree of a repo
    /// starts with the same pattern. An explicitly picked color renders solid.
    static func paneTint(for info: GitInfo, overrides: [String: TabColor] = [:]) -> PaneTint? {
        let identity = info.repoPath + (info.worktreeName ?? "")
        if let picked = overrides[identity] {
            return PaneTint(stops: [picked])
        }
        guard let own = colorForGitInfo(info, overrides: overrides) else { return nil }

        let parentInfo = GitInfo(
            repoName: info.repoName,
            branchName: nil,
            worktreeName: nil,
            repoPath: info.repoPath
        )
        let parentStops: [TabColor]
        if let picked = overrides[parentInfo.repoPath] {
            parentStops = [picked]
        } else if let parentPrimary = colorForGitInfo(parentInfo, overrides: overrides) {
            parentStops = [
                secondaryColor(for: parentInfo.repoPath, excluding: parentPrimary),
                parentPrimary
            ]
        } else {
            parentStops = [own]
        }

        guard info.worktreeName != nil else { return PaneTint(stops: parentStops) }
        return PaneTint(stops: parentStops + [own])
    }

    /// Resolve the pane tint for a directory.
    /// Priority: tab override (always solid) > git signature > nil.
    static func resolvedPaneTint(
        tabColorOverride: TabColor?,
        surfaceDirectory: String?,
        repoColorOverrides: [String: TabColor]
    ) -> PaneTint? {
        if let tabColorOverride {
            return PaneTint(stops: [tabColorOverride])
        }
        guard let dir = surfaceDirectory, let info = GitInfo.from(path: dir) else {
            return nil
        }
        return paneTint(for: info, overrides: repoColorOverrides)
    }
}

/// Ordered gradient stops for a pane, leading edge to trailing edge. One stop
/// renders solid, two is a repo's own signature, and three is a worktree
/// carrying its parent repo's pair ahead of its own color.
struct PaneTint: Equatable {
    let stops: [TabColor]

    init(stops: [TabColor]) {
        self.stops = stops.isEmpty ? [.gray] : stops
    }

    /// The color to use wherever only one can be shown. Always the trailing
    /// stop: a repo's own color, or a worktree's own color.
    var primary: TabColor { stops.last ?? .gray }

    /// The leading stop, used for the tab row's left edge bar.
    var leading: TabColor { stops.first ?? .gray }

    var isGradient: Bool { stops.count > 1 }
}
