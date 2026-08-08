import Foundation

extension TabColor {
    /// The long-standing repo color hash. Kept exactly as-is so existing tabs
    /// keep the color you already recognize.
    static func polynomialHash(_ identity: String) -> UInt64 {
        identity.utf8.reduce(UInt64(0)) { ($0 &+ UInt64($1)) &* 31 }
    }

    /// Derive a color from git repo identity.
    /// Same repo+worktree always produces the same color.
    /// Returns nil if not in a git repo (no tinting).
    static func colorForGitInfo(_ gitInfo: GitInfo?) -> TabColor? {
        guard let gitInfo else { return nil }
        let identity = gitInfo.repoPath + (gitInfo.worktreeName ?? "")
        // Gray is reserved for "no git repo" -- exclude it from the hash palette
        let colors = TabColor.allCases.filter { $0 != .gray }
        return colors[Int(polynomialHash(identity) % UInt64(colors.count))]
    }

    /// Derive a color from a directory path via its git repo.
    /// Returns nil if not in a git repo.
    static func colorForWorktree(_ dir: String?) -> TabColor? {
        guard let dir else { return nil }
        return colorForGitInfo(GitInfo.from(path: dir))
    }

    /// The repo identity string for a directory, used as the key in overrides.
    /// Returns nil if not in a git repo.
    static func repoIdentity(for dir: String?) -> String? {
        guard let dir, let gitInfo = GitInfo.from(path: dir) else { return nil }
        return gitInfo.repoPath + (gitInfo.worktreeName ?? "")
    }

    /// FNV-1a, independent of the polynomial hash behind `colorForGitInfo`, so a
    /// repo's two stops are uncorrelated.
    private static func mixedHash(_ identity: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in identity.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return hash
    }

    /// Pick a stop for `identity`, skipping every color whose hue family is
    /// already spoken for. Returns nil only if the palette is exhausted.
    static func knockout(
        for identity: String,
        avoiding taken: [TintStop],
        mixed: Bool = true
    ) -> TabColor? {
        let usedFamilies = Set(taken.map(\.hueFamily))
        let colors = TabColor.allCases.filter {
            $0 != .gray && !usedFamilies.contains($0.hueFamily)
        }
        guard !colors.isEmpty else { return nil }
        let hash = mixed ? mixedHash(identity) : polynomialHash(identity)
        return colors[Int(hash % UInt64(colors.count))]
    }

    /// Gradient stops for a git location. A repo gets its own two-color
    /// signature. A worktree carries its parent repo's signature on the leading
    /// edge and its own color on the trailing edge, so every worktree of a repo
    /// starts with the same pattern. A picked override renders using its own
    /// stops, solid or gradient.
    static func paneTint(for info: GitInfo, overrides: [String: PaneTint] = [:]) -> PaneTint? {
        let identity = info.repoPath + (info.worktreeName ?? "")
        if let picked = overrides[identity] { return picked }
        guard let own = colorForGitInfo(info) else { return nil }

        let parentInfo = GitInfo(
            repoName: info.repoName,
            branchName: nil,
            worktreeName: nil,
            repoPath: info.repoPath
        )
        let parentStops: [TintStop]
        if let picked = overrides[parentInfo.repoPath] {
            parentStops = picked.stops
        } else if let parentPrimary = colorForGitInfo(parentInfo) {
            let leading = knockout(for: parentInfo.repoPath, avoiding: [.named(parentPrimary)])
            parentStops = [.named(leading ?? parentPrimary), .named(parentPrimary)]
        } else {
            parentStops = [.named(own)]
        }

        guard info.worktreeName != nil else { return PaneTint(stops: parentStops) }
        // The worktree's own stop knocks out every parent family, so all
        // rendered bands stay tellable apart.
        let ownStop = knockout(for: identity, avoiding: parentStops, mixed: false)
        // Keep only the parent's leading stops so the worktree's own trailing
        // stop always survives PaneTint's clamp to maxStops -- the own stop is
        // what makes a worktree distinguishable from its parent and siblings,
        // so it must never be the stop that gets dropped.
        let leadingParentStops = Array(parentStops.prefix(PaneTint.maxStops - 1))
        return PaneTint(stops: leadingParentStops + [.named(ownStop ?? own)])
    }

    /// Resolve the pane tint for a surface.
    /// Priority: surface override > tab override > repo override > git signature > nil.
    static func resolvedPaneTint(
        surfaceOverride: PaneTint?,
        tabColorOverride: PaneTint?,
        surfaceDirectory: String?,
        repoColorOverrides: [String: PaneTint]
    ) -> PaneTint? {
        if let surfaceOverride { return surfaceOverride }
        if let tabColorOverride { return tabColorOverride }
        guard let dir = surfaceDirectory, let info = GitInfo.from(path: dir) else {
            return nil
        }
        return paneTint(for: info, overrides: repoColorOverrides)
    }
}
