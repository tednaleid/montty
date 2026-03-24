import Foundation

@Observable
final class Tab: Identifiable {
    let id: UUID
    var name: String
    var autoName: String
    var color: TabColor
    var position: Int
    var workingDirectory: String?
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

    /// Computed metadata for tab display, decoupled from AppKit/Ghostty.
    var tabInfo: TabInfo {
        TabInfo.from(tab: TabProperties(
            name: name,
            autoName: autoName,
            workingDirectory: workingDirectory,
            splitRoot: splitRoot,
            focusedLeafID: focusedLeafID,
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
        color: TabColor = .auto,
        position: Int = 0,
        workingDirectory: String? = nil,
        surfaceID: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.autoName = autoName
        self.color = color
        self.position = position
        self.workingDirectory = workingDirectory
        let leaf = SurfaceLeaf(surfaceID: surfaceID)
        self.splitRoot = .leaf(leaf)
        self.focusedLeafID = leaf.id
    }

    /// Init for session restoration with a pre-built split tree.
    init(
        id: UUID,
        name: String,
        color: TabColor,
        position: Int
    ) {
        self.id = id
        self.name = name
        self.autoName = ""
        self.color = color
        self.position = position
        self.workingDirectory = nil
        self.splitRoot = .leaf(SurfaceLeaf())
        self.focusedLeafID = nil
    }
}
