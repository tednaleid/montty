// ABOUTME: Builds the /surfaces "color" object for one surface, resolving the
// ABOUTME: same precedence chain that paints it so the two can never disagree.
#if DEBUG
import Foundation

extension DebugServer {
    /// Per-surface color state: what is painted, and which scope produced it.
    static func colorEntry(leaf: SurfaceLeaf, tab: Tab, appDelegate: AppDelegate) -> [String: Any] {
        let surfaceOverride = tab.surfaceColorOverrides[leaf.surfaceID]
        let tabOverride = tab.colorOverride
        let directory = tab.effectiveSurfaceDirectories[leaf.surfaceID]
        let gitInfo = directory.flatMap(GitInfo.from(path:))
        let identity = gitInfo.map { TabColor.repoIdentity(for: $0) }
        let repoOverride = identity.flatMap { appDelegate.repoColorOverrides[$0] }

        let effective = TabColor.resolvedPaneTint(
            surfaceOverride: surfaceOverride,
            tabColorOverride: tabOverride,
            surfaceDirectory: directory,
            repoColorOverrides: appDelegate.repoColorOverrides
        ) ?? PaneTint(stops: [.named(.gray)])

        var entry: [String: Any] = [
            "effective": effective.stops.map(\.text),
            "source": TabColor.resolvedTintSource(
                surfaceOverride: surfaceOverride, tabColorOverride: tabOverride,
                repoOverride: repoOverride, gitInfo: gitInfo
            ),
            "surface_override": NSNull(),
            "tab_override": NSNull(),
            "repo_override": NSNull()
        ]
        if let surfaceOverride {
            entry["surface_override"] = surfaceOverride.stops.map(\.text)
        }
        if let tabOverride {
            entry["tab_override"] = tabOverride.stops.map(\.text)
        }
        if let identity, let repoOverride {
            entry["repo_override"] = ["identity": identity, "stops": repoOverride.stops.map(\.text)]
        }
        return entry
    }
}
#endif
