import Foundation

@Observable
final class Tab: Identifiable {
    let id: UUID
    var name: String
    var autoName: String
    var position: Int
    var splitRoot: SplitNode
    var focusedLeafID: UUID?
    /// Per-surface terminal titles, keyed by surfaceID.
    var surfaceTitles: [UUID: String] = [:]
    /// Per-surface Claude Code state, keyed by MONTTY_SURFACE_ID.
    var claudeStates: [String: ClaudeCodeStatus.State] = [:]
    /// Maps Ghostty surfaceID -> MONTTY_SURFACE_ID for hook routing.
    var surfaceToMonttyID: [UUID: String] = [:]
    /// Per-surface working directories, keyed by surfaceID.
    var surfaceDirectories: [UUID: String] = [:]

    var displayName: String {
        name.isEmpty ? autoName : name
    }

    /// The effective color for this tab, derived from the focused surface's
    /// git repo with optional overrides.
    func effectiveColor(overrides: [String: TabColor] = [:]) -> TabColor {
        let dir = focusedSurfaceID.flatMap { surfaceDirectories[$0] }
        return TabColor.colorForWorktree(dir, overrides: overrides) ?? .gray
    }

    /// Computed metadata for tab display, decoupled from AppKit/Ghostty.
    var tabInfo: TabInfo {
        TabInfo.from(tab: TabProperties(
            name: name,
            autoName: autoName,
            splitRoot: splitRoot,
            focusedLeafID: focusedLeafID,
            surfaceDirectories: surfaceDirectories,
            surfaceTitles: surfaceTitles,
            claudeStates: claudeStates,
            surfaceToMonttyID: surfaceToMonttyID
        ))
    }

    /// The surfaceID of the focused leaf, or the first leaf if none focused.
    var focusedSurfaceID: UUID? {
        if let focusedLeafID = focusedLeafID,
           let leaves = Optional(SplitTree.allLeaves(node: splitRoot)),
           let leaf = leaves.first(where: { $0.id == focusedLeafID }) {
            return leaf.surfaceID
        }
        return SplitTree.allLeaves(node: splitRoot).first?.surfaceID
    }

    /// All surface IDs in this tab's split tree.
    var allSurfaceIDs: [UUID] {
        SplitTree.allLeaves(node: splitRoot).map(\.surfaceID)
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        autoName: String = "",
        position: Int = 0,
        surfaceID: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.autoName = autoName
        self.position = position
        let leaf = SurfaceLeaf(surfaceID: surfaceID)
        self.splitRoot = .leaf(leaf)
        self.focusedLeafID = leaf.id
    }

    /// Init for session restoration with a pre-built split tree.
    init(
        id: UUID,
        name: String,
        position: Int
    ) {
        self.id = id
        self.name = name
        self.autoName = ""
        self.position = position
        self.splitRoot = .leaf(SurfaceLeaf())
        self.focusedLeafID = nil
    }
}
