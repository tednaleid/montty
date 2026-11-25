// ABOUTME: The adapter between a Tab's stored state and ControlService, shared
// ABOUTME: by the montty CLI, the tab context menu, and the Claude Code hooks.

import Foundation

extension Tab {
    /// Resolve one of this tab's surfaces to the reference ControlService needs.
    func surfaceRef(for surfaceID: UUID) -> SurfaceRef? {
        guard let monttyID = surfaceToMonttyID[surfaceID],
              let leaf = SplitTree.findLeaf(node: splitRoot, surfaceID: surfaceID)
        else { return nil }
        return SurfaceRef(
            monttyID: monttyID,
            surfaceID: surfaceID,
            leafID: leaf.id,
            tabID: id,
            directory: effectiveSurfaceDirectories[surfaceID]
        )
    }

    /// Runs a control command for a caller that holds no shared settings, so a
    /// command at the repo or app scope changes nothing it can see.
    @discardableResult
    func applyControl(
        _ command: ControlCommand,
        surfaceID: UUID,
        repoColorOverrides: inout [String: PaneTint],
        gitInfoProvider: (String) -> GitInfo? = GitInfo.from(path:),
        now: Date = Date()
    ) -> ControlResult {
        var shared = SharedSettings()
        return applyControl(
            command, surfaceID: surfaceID, repoColorOverrides: &repoColorOverrides,
            shared: &shared, gitInfoProvider: gitInfoProvider, now: now
        )
    }

    /// Run a control command against this tab and write the result back onto it.
    /// Repo colors and the shared settings belong to every tab, so they travel
    /// in and out.
    @discardableResult
    func applyControl(
        _ command: ControlCommand,
        surfaceID: UUID,
        repoColorOverrides: inout [String: PaneTint],
        shared: inout SharedSettings,
        gitInfoProvider: (String) -> GitInfo? = GitInfo.from(path:),
        now: Date = Date()
    ) -> ControlResult {
        guard let target = surfaceRef(for: surfaceID) else {
            return .rejected(.unknownSurface)
        }
        var state = ControlState(
            tabName: name,
            displayName: tabInfo.autoDisplayName,
            surfaceColorOverrides: surfaceColorOverrides,
            tabColorOverride: colorOverride,
            repoColorOverrides: repoColorOverrides,
            activityStates: activityStates,
            activityWaitingSince: activityWaitingSince,
            surfaceResumeCommands: resumeCommands,
            tabMinimapVisibility: self.minimapVisibility,
            tabMinimapHeight: minimapHeight,
            surfaceNames: surfaceNames,
            surfaceSettings: surfaceSettings,
            tabSettings: settings,
            shared: shared
        )
        let result = ControlService.apply(
            command, target: target, to: &state,
            gitInfoProvider: gitInfoProvider, now: now
        )
        name = state.tabName
        surfaceColorOverrides = state.surfaceColorOverrides
        colorOverride = state.tabColorOverride
        activityStates = state.activityStates
        activityWaitingSince = state.activityWaitingSince
        resumeCommands = state.surfaceResumeCommands
        self.minimapVisibility = state.tabMinimapVisibility
        minimapHeight = state.tabMinimapHeight
        surfaceNames = state.surfaceNames
        surfaceSettings = state.surfaceSettings
        settings = state.tabSettings
        repoColorOverrides = state.repoColorOverrides
        shared = state.shared
        return result
    }
}
