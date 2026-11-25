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
    /// What the sidebar and tab row show for this tab, which is the name
    /// override when set and the focused pane's directory otherwise.
    var displayName: String
    var surfaceColorOverrides: [UUID: PaneTint]
    var tabColorOverride: PaneTint?
    var repoColorOverrides: [String: PaneTint]
    var activityStates: [String: ActivityStatus.State]
    var activityWaitingSince: [String: Date]
    var surfaceResumeCommands: [UUID: String]
    var tabMinimapVisibility: MinimapVisibility?
    var tabMinimapHeight: Double?
    /// Per-surface name, keyed by surfaceID. The tab shows the focused
    /// surface's name ahead of its own.
    var surfaceNames: [UUID: String] = [:]
    var surfaceSettings: [UUID: SettingOverrides] = [:]
    var tabSettings = SettingOverrides()
    /// The app's values and each repo's overrides, shared by every tab.
    var shared = SharedSettings()
}

extension ControlState {
    /// Sets a strength at one scope. A nil value removes the override there,
    /// and an entry left with no overrides is removed with it. At the app
    /// scope nil returns the strength to its default.
    mutating func setStrength(
        _ setting: StrengthSetting, _ value: Double?, at scope: SettingScope,
        surfaceID: UUID, repoIdentity: String?
    ) {
        switch scope {
        case .surface:
            var overrides = surfaceSettings[surfaceID] ?? SettingOverrides()
            overrides[setting] = value
            surfaceSettings[surfaceID] = overrides.isEmpty ? nil : overrides
        case .tab:
            tabSettings[setting] = value
        case .repo:
            guard let repoIdentity else { return }
            var overrides = shared.repos[repoIdentity] ?? SettingOverrides()
            overrides[setting] = value
            shared.repos[repoIdentity] = overrides.isEmpty ? nil : overrides
        case .app:
            shared.app[setting] = value ?? setting.default
        }
    }
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

        case .setName, .clearName, .setSurfaceName:
            setName(command, target: target, to: &state)
            return .applied

        case .setStatus(let status):
            setStatus(status, target: target, to: &state, now: now)
            return .applied

        case .setResumeCommand(let command):
            state.surfaceResumeCommands[target.surfaceID] = command
            return .applied

        case .setMinimapVisibility, .setTabMinimapVisibility, .setMinimapHeight:
            setMinimap(command, to: &state)
            return .applied

        case .setStrength(let setting, let scope, let value):
            // Repo scope needs a git identity, so it is the only scope that
            // can be rejected.
            let identity = scope == .repo
                ? repoIdentity(target: target, gitInfoProvider: gitInfoProvider) : nil
            guard scope != .repo || identity != nil else { return .rejected(.notInRepo) }
            state.setStrength(
                setting, value, at: scope, surfaceID: target.surfaceID, repoIdentity: identity)
            return .applied

        case .newTab, .takeLaunch:
            // These open a tab and hand over its command rather than changing
            // a tab. AppDelegate.applyControl handles them before a command
            // reaches here; this case keeps the switch exhaustive.
            return .applied

        case .info:
            return .read(info(target: target, state: state,
                              gitInfoProvider: gitInfoProvider))
        }
    }

    private static func setName(
        _ command: ControlCommand, target: SurfaceRef, to state: inout ControlState
    ) {
        switch command {
        case .setName(let name): state.tabName = name
        case .clearName: state.tabName = ""
        case .setSurfaceName(let name):
            state.surfaceNames[target.surfaceID] = (name ?? "").isEmpty ? nil : name
        default: break
        }
    }

    /// The minimap height has only a tab and an app scope, so any other scope
    /// leaves the state alone.
    private static func setMinimap(_ command: ControlCommand, to state: inout ControlState) {
        switch command {
        case .setMinimapVisibility(let visibility):
            state.shared.app.minimapVisibility = visibility
        case .setTabMinimapVisibility(let visibility):
            state.tabMinimapVisibility = visibility
        case .setMinimapHeight(.tab, let height):
            state.tabMinimapHeight = height
        case .setMinimapHeight(.app, let height):
            state.shared.app.minimapHeight = height ?? MinimapHeight.default
        default: break
        }
    }

    /// Status runs through the hook state machine so the CLI and the hooks
    /// cannot drift apart.
    private static func setStatus(
        _ status: ActivityStatus.State?,
        target: SurfaceRef,
        to state: inout ControlState,
        now: Date
    ) {
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
        return TabColor.repoIdentity(for: info)
    }

    private static func info(
        target: SurfaceRef,
        state: ControlState,
        gitInfoProvider: (String) -> GitInfo?
    ) -> ControlInfo {
        let gitInfo = target.directory.flatMap(gitInfoProvider)
        let identity = gitInfo.map { TabColor.repoIdentity(for: $0) }
        let repoTint = identity.flatMap { state.repoColorOverrides[$0] }

        let effective = TabColor.resolvedPaneTint(
            surfaceOverride: state.surfaceColorOverrides[target.surfaceID],
            tabColorOverride: state.tabColorOverride,
            surfaceDirectory: target.directory,
            repoColorOverrides: state.repoColorOverrides,
            gitInfoProvider: gitInfoProvider
        )

        return ControlInfo(
            surfaceID: target.monttyID,
            leafID: target.leafID.uuidString,
            tabID: target.tabID.uuidString,
            tabName: state.tabName.isEmpty ? state.displayName : state.tabName,
            tabNameIsOverride: !state.tabName.isEmpty,
            surfaceName: state.surfaceNames[target.surfaceID],
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
            status: state.activityStates[target.monttyID].map(\.wireName),
            resumeCommand: state.surfaceResumeCommands[target.surfaceID],
            settings: settings(target: target, state: state, repoIdentity: identity)
        )
    }

    private static func settings(
        target: SurfaceRef, state: ControlState, repoIdentity: String?
    ) -> ControlInfo.Settings {
        let app = state.shared.app
        let surface = state.surfaceSettings[target.surfaceID]
        let repo = repoIdentity.flatMap { state.shared.repos[$0] }
        func strength(_ setting: StrengthSetting) -> ControlInfo.Scoped<Double> {
            .init(
                surface: surface?[setting], tab: state.tabSettings[setting],
                repo: repo?[setting], app: app[setting],
                effective: setting.resolve(
                    surface: surface, tab: state.tabSettings, repo: repo, app: app)
            )
        }
        return ControlInfo.Settings(
            surfaceTintStrength: strength(.surfaceTint),
            tabTintStrength: strength(.tabTint),
            minimap: .init(
                tab: state.tabMinimapVisibility?.text,
                app: app.minimapVisibility.text,
                effective: (state.tabMinimapVisibility ?? app.minimapVisibility).text
            ),
            minimapHeight: .init(
                tab: state.tabMinimapHeight, app: app.minimapHeight,
                effective: state.tabMinimapHeight ?? app.minimapHeight
            )
        )
    }

    /// Pair two optionals, yielding nil unless both are present.
    private static func zip2<A, B>(_ first: A?, _ second: B?) -> (A, B)? {
        guard let first, let second else { return nil }
        return (first, second)
    }
}
