import Foundation

extension TabColor {
    /// The long-standing repo color hash. Kept exactly as-is so existing tabs
    /// keep the color you already recognize.
    static func polynomialHash(_ identity: String) -> UInt64 {
        identity.utf8.reduce(UInt64(0)) { ($0 &+ UInt64($1)) &* 31 }
    }

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
        // Gray is reserved for "no git repo" -- exclude it from the hash palette
        let colors = TabColor.allCases.filter { $0 != .gray }
        return colors[Int(polynomialHash(identity) % UInt64(colors.count))]
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
        resolvedPaneTint(
            tabColorOverride: tabColorOverride,
            surfaceDirectory: surfaceDirectory,
            repoColorOverrides: repoColorOverrides
        )?.primary
    }

    /// The repo identity string for a directory, used as the key in overrides.
    /// Returns nil if not in a git repo.
    static func repoIdentity(for dir: String?) -> String? {
        guard let dir, let gitInfo = GitInfo.from(path: dir) else { return nil }
        return gitInfo.repoPath + (gitInfo.worktreeName ?? "")
    }

    /// Hue families collapse each base/bright pair, which read as one color at a
    /// glance. Knockout removes a whole family so a gradient never sets green
    /// beside brightGreen.
    enum HueFamily: Hashable {
        case red, green, yellow, blue, magenta, cyan, neutral
    }

    var hueFamily: HueFamily {
        switch self {
        case .red, .brightRed: .red
        case .green, .brightGreen: .green
        case .yellow, .brightYellow: .yellow
        case .blue, .brightBlue: .blue
        case .magenta, .brightMagenta: .magenta
        case .cyan, .brightCyan: .cyan
        case .neutral, .neutralBright, .gray: .neutral
        }
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
        avoiding taken: [TabColor],
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
            let leading = knockout(for: parentInfo.repoPath, avoiding: [parentPrimary])
            parentStops = [leading ?? parentPrimary, parentPrimary]
        } else {
            parentStops = [own]
        }

        guard info.worktreeName != nil else { return PaneTint(stops: parentStops) }
        // The worktree's own stop knocks out both parent families, so all three
        // bands stay tellable apart.
        let ownStop = knockout(for: identity, avoiding: parentStops, mixed: false)
        return PaneTint(stops: parentStops + [ownStop ?? own])
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
