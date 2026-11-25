// ABOUTME: Model state for one tab: split tree, focused pane, name, color overrides,
// ABOUTME: and per-surface titles, directories, and Claude activity from hook events.
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
    /// The `activityWaitingSince` timestamp of a `.waiting` the control CLI set,
    /// keyed by MONTTY_SURFACE_ID. A hook-driven `.waiting` stamps a fresh time,
    /// so a tag only ever describes the episode that recorded it.
    var activityWaitingFromControl: [String: Date] = [:]
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
    /// Per-surface resume command, keyed by surfaceID. Typed at the surface's
    /// prompt, unexecuted, when a relaunch restores it.
    var resumeCommands: [UUID: String] = [:]
    /// Tab-level color override. Beats repo/worktree colors for all surfaces in this tab.
    var colorOverride: PaneTint?
    /// Tab-level minimap visibility. Beats the app-wide value when set.
    var minimapVisibility: MinimapVisibility?
    /// Tab-level minimap height in points. Beats the app value when set.
    var minimapHeight: Double?
    /// Per-surface name, keyed by surfaceID. The tab shows its focused
    /// surface's name ahead of its own.
    var surfaceNames: [UUID: String] = [:]
    /// Per-surface strength overrides, keyed by surfaceID. Beat the tab's.
    var surfaceSettings: [UUID: SettingOverrides] = [:]
    /// Tab-level strength overrides. Beat the repo's and the app's.
    var settings = SettingOverrides()

    var displayName: String {
        let shown = focusedSurfaceID.flatMap { surfaceNames[$0] } ?? name
        return shown.isEmpty ? autoName : shown
    }

    /// A strength as `surfaceID` resolves it: its own value, then this tab's,
    /// then its repo's, then the app's. The repo is only looked up when some
    /// repo has an override.
    func strength(
        _ setting: StrengthSetting,
        for surfaceID: UUID?,
        shared: SharedSettings,
        gitInfoProvider: (String) -> GitInfo? = GitInfo.from(path:)
    ) -> Double {
        var repo: SettingOverrides?
        if !shared.repos.isEmpty, let surfaceID,
           let info = effectiveSurfaceDirectories[surfaceID].flatMap(gitInfoProvider) {
            repo = shared.repos[TabColor.repoIdentity(for: info)]
        }
        return setting.resolve(
            surface: surfaceID.flatMap { surfaceSettings[$0] },
            tab: settings, repo: repo, app: shared.app
        )
    }

    /// The surface tint strength of every surface in this tab.
    func surfaceTintStrengths(
        shared: SharedSettings,
        gitInfoProvider: (String) -> GitInfo? = GitInfo.from(path:)
    ) -> [UUID: Double] {
        Dictionary(uniqueKeysWithValues: allSurfaceIDs.map { surfaceID in
            (surfaceID, strength(.surfaceTint, for: surfaceID, shared: shared,
                                 gitInfoProvider: gitInfoProvider))
        })
    }

    /// The strength of the wash behind this tab in the sidebar, which follows
    /// the focused surface as the tab's color does.
    func tabTintStrength(
        shared: SharedSettings,
        gitInfoProvider: (String) -> GitInfo? = GitInfo.from(path:)
    ) -> Double {
        strength(.tabTint, for: focusedSurfaceID, shared: shared, gitInfoProvider: gitInfoProvider)
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
            surfaceToMonttyID: surfaceToMonttyID,
            surfaceNames: surfaceNames
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

    /// The shell's working directory for the focused pane -- the directory the
    /// tab is in. The shell pwd rather than the effective one, matching what a
    /// restored pane actually opens in.
    var focusedDirectory: String? {
        focusedSurfaceID.flatMap { surfaceDirectories[$0] }
    }

    /// All surface IDs in this tab's split tree.
    var allSurfaceIDs: [UUID] {
        SplitTree.allLeaves(node: splitRoot).map(\.surfaceID)
    }

    /// Whether this tab's row shows its minimap, given the app-wide visibility.
    /// Only a status on a surface still in the split tree counts, which is the
    /// set the minimap would draw.
    func showsMinimap(global: MinimapVisibility) -> Bool {
        let surfaceIDs = allSurfaceIDs
        let hasStatus = surfaceIDs.contains { surfaceID in
            surfaceToMonttyID[surfaceID].flatMap { activityStates[$0] } != nil
        }
        return (minimapVisibility ?? global).shows(
            surfaceCount: surfaceIDs.count, hasStatus: hasStatus
        )
    }

    /// The leaf a jump or a row click lands on: the focused one, or the first
    /// in tree order when none is recorded.
    var focusedOrFirstLeafID: UUID? {
        let leaves = SplitTree.allLeaves(node: splitRoot)
        return leaves.first { $0.id == focusedLeafID }?.id ?? leaves.first?.id
    }

    /// Point each leaf at the surface created for it. Leaves not named in
    /// `bindings` keep the surface they already have. A monttyID, resume
    /// command, name, or strength override already recorded for the leaf's
    /// placeholder surface carries over to the new id; a monttyID already recorded under the new id (the
    /// shell may have registered it before this call) is left untouched.
    func bindSurfaces(_ bindings: [UUID: UUID]) {
        splitRoot = SplitTree.mapLeaves(node: splitRoot) { leaf in
            guard let surfaceID = bindings[leaf.id] else { return leaf }
            if let monttyID = surfaceToMonttyID.removeValue(forKey: leaf.surfaceID) {
                surfaceToMonttyID[surfaceID] = monttyID
            }
            if let command = resumeCommands.removeValue(forKey: leaf.surfaceID) {
                resumeCommands[surfaceID] = command
            }
            if let name = surfaceNames.removeValue(forKey: leaf.surfaceID) {
                surfaceNames[surfaceID] = name
            }
            if let overrides = surfaceSettings.removeValue(forKey: leaf.surfaceID) {
                surfaceSettings[surfaceID] = overrides
            }
            return SurfaceLeaf(id: leaf.id, surfaceID: surfaceID)
        }
    }

    /// Safety net: if the given surface is currently `.waiting`, transition to `.working`.
    /// Called when a new title arrives — a title change is strong evidence Claude is active.
    /// A `.waiting` the control CLI set is exempt, because an ordinary shell reprints
    /// its title at every prompt and would clear the state the moment it was set.
    /// Returns true if the state changed.
    @discardableResult
    func clearWaitingOnTitleChange(for surfaceID: UUID) -> Bool {
        guard let monttyID = surfaceToMonttyID[surfaceID],
              activityStates[monttyID] == .waiting,
              !waitingCameFromControl(monttyID) else { return false }
        activityStates[monttyID] = .working
        activityWaitingSince.removeValue(forKey: monttyID)
        return true
    }

    /// Whether this surface's current `.waiting` episode came from the control CLI.
    private func waitingCameFromControl(_ monttyID: String) -> Bool {
        guard let tagged = activityWaitingFromControl[monttyID],
              let since = activityWaitingSince[monttyID] else { return false }
        return tagged == since
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
            activityWaitingFromControl.removeValue(forKey: monttyID)
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
