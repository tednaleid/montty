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
    /// Per-surface activity state populated by hook events, keyed by MONTTY_SURFACE_ID.
    var activityStates: [String: ActivityStatus.State] = [:]
    /// Timestamps for when each surface entered `.waiting`, keyed by MONTTY_SURFACE_ID.
    /// Used for the timeout sweep that clears stuck `*?` indicators.
    var activityWaitingSince: [String: Date] = [:]
    /// Maps Ghostty surfaceID -> MONTTY_SURFACE_ID for hook routing.
    var surfaceToMonttyID: [UUID: String] = [:]
    /// Per-surface working directories, keyed by surfaceID.
    /// These come from the parent shell via Ghostty's PWD action (OSC 7 / chpwd).
    var surfaceDirectories: [UUID: String] = [:]
    /// Per-surface cwd as reported by Claude Code's hooks, keyed by MONTTY_SURFACE_ID.
    /// Set on every hook event with a cwd; cleared on session-end. Wins over the
    /// shell pwd because Claude can `cd` into a worktree without the parent shell
    /// noticing (no chpwd fires from a subprocess).
    var claudeDirectories: [String: String] = [:]
    /// Per-surface color override, keyed by surfaceID. Beats the tab override.
    var surfaceColorOverrides: [UUID: PaneTint] = [:]
    /// Tab-level color override. Beats repo/worktree colors for all surfaces in this tab.
    var colorOverride: PaneTint?

    var displayName: String {
        name.isEmpty ? autoName : name
    }

    /// Per-surface effective directory: Claude's reported cwd if active, else the shell pwd.
    var effectiveSurfaceDirectories: [UUID: String] {
        var dirs = surfaceDirectories
        for (uuid, monttyID) in surfaceToMonttyID {
            if let claudeCwd = claudeDirectories[monttyID] {
                dirs[uuid] = claudeCwd
            }
        }
        return dirs
    }

    /// The effective color for this tab. Priority: surface > tab > repo > git hash > gray.
    func effectiveColor(overrides: [String: PaneTint] = [:]) -> TintStop {
        effectivePaneTint(overrides: overrides).primary
    }

    /// The effective tint for this tab, including the worktree-gradient secondary
    /// stop when the focused pane is in a linked worktree. Falls back to a solid
    /// gray tint when there's no git info.
    func effectivePaneTint(overrides: [String: PaneTint] = [:]) -> PaneTint {
        let dirs = effectiveSurfaceDirectories
        let surfaceID = focusedSurfaceID
        let dir = surfaceID.flatMap { dirs[$0] }
        return TabColor.resolvedPaneTint(
            surfaceOverride: surfaceID.flatMap { surfaceColorOverrides[$0] },
            tabColorOverride: colorOverride,
            surfaceDirectory: dir,
            repoColorOverrides: overrides
        ) ?? PaneTint(stops: [.named(.gray)])
    }

    /// Computed metadata for tab display, decoupled from AppKit/Ghostty.
    var tabInfo: TabInfo {
        TabInfo.from(tab: TabProperties(
            name: name,
            autoName: autoName,
            splitRoot: splitRoot,
            focusedLeafID: focusedLeafID,
            surfaceDirectories: effectiveSurfaceDirectories,
            surfaceTitles: surfaceTitles,
            activityStates: activityStates,
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
              activityStates[monttyID] == .waiting else { return false }
        activityStates[monttyID] = .working
        activityWaitingSince.removeValue(forKey: monttyID)
        return true
    }

    /// Safety net: transition any surfaces stuck in `.waiting` for more than
    /// `threshold` seconds back to `.idle`. Protects against lost hook events.
    /// Returns the MONTTY_SURFACE_IDs that were transitioned.
    @discardableResult
    func sweepStaleWaiting(threshold: TimeInterval = 60, now: Date = Date()) -> [String] {
        var transitioned: [String] = []
        for (monttyID, since) in activityWaitingSince
        where activityStates[monttyID] == .waiting
            && now.timeIntervalSince(since) > threshold {
            activityStates[monttyID] = .idle
            transitioned.append(monttyID)
        }
        for monttyID in transitioned {
            activityWaitingSince.removeValue(forKey: monttyID)
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
