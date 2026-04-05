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
    /// Timestamps for when each surface entered `.waiting`, keyed by MONTTY_SURFACE_ID.
    /// Used for the timeout sweep that clears stuck `*?` indicators.
    var claudeWaitingSince: [String: Date] = [:]
    /// Maps Ghostty surfaceID -> MONTTY_SURFACE_ID for hook routing.
    var surfaceToMonttyID: [UUID: String] = [:]
    /// Per-surface working directories, keyed by surfaceID.
    var surfaceDirectories: [UUID: String] = [:]
    /// Tab-level color override. Beats repo/worktree colors for all surfaces in this tab.
    var colorOverride: TabColor?

    var displayName: String {
        name.isEmpty ? autoName : name
    }

    /// The effective color for this tab. Priority: tab override > repo override > git hash > gray.
    func effectiveColor(overrides: [String: TabColor] = [:]) -> TabColor {
        if let colorOverride { return colorOverride }
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

    /// Safety net: if the given surface is currently `.waiting`, transition to `.working`.
    /// Called when a new title arrives — a title change is strong evidence Claude is active.
    /// Returns true if the state changed.
    @discardableResult
    func clearWaitingOnTitleChange(for surfaceID: UUID) -> Bool {
        guard let monttyID = surfaceToMonttyID[surfaceID],
              claudeStates[monttyID] == .waiting else { return false }
        claudeStates[monttyID] = .working
        claudeWaitingSince.removeValue(forKey: monttyID)
        return true
    }

    /// Safety net: transition any surfaces stuck in `.waiting` for more than
    /// `threshold` seconds back to `.idle`. Protects against lost hook events.
    /// Returns the MONTTY_SURFACE_IDs that were transitioned.
    @discardableResult
    func sweepStaleWaiting(threshold: TimeInterval = 60, now: Date = Date()) -> [String] {
        var transitioned: [String] = []
        for (monttyID, since) in claudeWaitingSince
        where claudeStates[monttyID] == .waiting
            && now.timeIntervalSince(since) > threshold {
            claudeStates[monttyID] = .idle
            transitioned.append(monttyID)
        }
        for monttyID in transitioned {
            claudeWaitingSince.removeValue(forKey: monttyID)
        }
        return transitioned
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
