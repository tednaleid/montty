// ABOUTME: The one place styling and activity state is mutated, shared by the
// ABOUTME: montty CLI, the tab context menu, and the Claude Code hooks.

import Foundation

/// Identifies the surface a command targets. Adapters build this by resolving
/// a MONTTY_SURFACE_ID against the tab store, so ControlService never walks it.
struct SurfaceRef: Equatable {
    let monttyID: String
    let surfaceID: UUID
    let leafID: UUID
    let tabID: UUID
    /// Claude's reported cwd when present, otherwise the shell pwd.
    let directory: String?
}

/// A narrow view of exactly what a control command may change.
struct ControlState: Equatable {
    var tabName: String
    var autoName: String
    var surfaceColorOverrides: [UUID: PaneTint]
    var tabColorOverride: PaneTint?
    var repoColorOverrides: [String: PaneTint]
    var activityStates: [String: ActivityStatus.State]
    var activityWaitingSince: [String: Date]
}

enum ControlService {
    static func apply(
        _ command: ControlCommand,
        target: SurfaceRef,
        to state: inout ControlState,
        gitInfoProvider: (String) -> GitInfo? = GitInfo.from(path:),
        now: Date = Date()
    ) -> ControlResult {
        switch command {
        case .setColor(let scope, let tint):
            return setColor(scope, tint, target: target, to: &state,
                            gitInfoProvider: gitInfoProvider)

        case .clearColor(let scope):
            return setColor(scope, nil, target: target, to: &state,
                            gitInfoProvider: gitInfoProvider)

        case .setName(let name):
            state.tabName = name
            return .applied

        case .clearName:
            state.tabName = ""
            return .applied

        case .setStatus(let status):
            let event: ClaudeHookEvent
            switch status {
            case .working: event = .promptSubmit
            case .waiting: event = .notification
            case .idle: event = .stop
            case nil: event = .sessionEnd
            }
            _ = HookStateMachine.apply(
                event,
                surfaceID: target.monttyID,
                to: &state.activityStates,
                waitingSince: &state.activityWaitingSince,
                isKnownSurface: true,
                now: now
            )
            return .applied

        case .info:
            return .read(info(target: target, state: state,
                              gitInfoProvider: gitInfoProvider))
        }
    }

    /// A nil tint clears that scope. Repo scope needs a git identity, so it is
    /// the only scope that can be rejected.
    private static func setColor(
        _ scope: ControlScope,
        _ tint: PaneTint?,
        target: SurfaceRef,
        to state: inout ControlState,
        gitInfoProvider: (String) -> GitInfo?
    ) -> ControlResult {
        switch scope {
        case .surface:
            state.surfaceColorOverrides[target.surfaceID] = tint
        case .tab:
            state.tabColorOverride = tint
        case .repo:
            guard let identity = repoIdentity(target: target,
                                              gitInfoProvider: gitInfoProvider) else {
                return .rejected(.notInRepo)
            }
            state.repoColorOverrides[identity] = tint
        }
        return .applied
    }

    private static func repoIdentity(
        target: SurfaceRef,
        gitInfoProvider: (String) -> GitInfo?
    ) -> String? {
        guard let directory = target.directory,
              let info = gitInfoProvider(directory) else { return nil }
        return info.repoPath + (info.worktreeName ?? "")
    }

    private static func info(
        target: SurfaceRef,
        state: ControlState,
        gitInfoProvider: (String) -> GitInfo?
    ) -> ControlInfo {
        let gitInfo = target.directory.flatMap(gitInfoProvider)
        let identity = gitInfo.map { $0.repoPath + ($0.worktreeName ?? "") }
        let repoTint = identity.flatMap { state.repoColorOverrides[$0] }

        let effective = TabColor.resolvedPaneTint(
            surfaceOverride: state.surfaceColorOverrides[target.surfaceID],
            tabColorOverride: state.tabColorOverride,
            surfaceDirectory: target.directory,
            repoColorOverrides: state.repoColorOverrides
        )

        return ControlInfo(
            surfaceID: target.monttyID,
            leafID: target.leafID.uuidString,
            tabID: target.tabID.uuidString,
            tabName: state.tabName.isEmpty ? state.autoName : state.tabName,
            tabNameIsOverride: !state.tabName.isEmpty,
            scopes: ControlInfo.Scopes(
                surface: state.surfaceColorOverrides[target.surfaceID].map(TintPayload.init),
                tab: state.tabColorOverride.map(TintPayload.init),
                repo: zip2(identity, repoTint).map {
                    RepoTintPayload(identity: $0, stops: $1.stops.map(\.text))
                }
            ),
            effective: effective.map(TintPayload.init),
            git: gitInfo.map {
                ControlInfo.Git(
                    repoName: $0.repoName, branch: $0.branchName,
                    worktree: $0.worktreeName, repoPath: $0.repoPath
                )
            },
            status: state.activityStates[target.monttyID].map { String(describing: $0) }
        )
    }

    /// Pair two optionals, yielding nil unless both are present.
    private static func zip2<A, B>(_ first: A?, _ second: B?) -> (A, B)? {
        guard let first, let second else { return nil }
        return (first, second)
    }
}
