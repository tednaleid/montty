// ABOUTME: The driving port: every mutation an outside actor can ask montty
// ABOUTME: for, plus the result and info payload those actors read back.

import Foundation

/// Which layer of the color precedence a command targets.
enum ControlScope: String, Codable, CaseIterable {
    case surface, tab, repo
}

/// Opacity of the surface tint overlay, app-wide rather than scoped to any
/// surface, tab, or repo.
enum SurfaceTintStrength {
    static let `default`: Double = 0.12
    /// 0 hides the tint entirely. Capped at 0.5, not 1: the overlay is a flat
    /// fill, so opacity 1 replaces every pixel and hides the pane's content
    /// completely rather than just tinting it.
    static let range: ClosedRange<Double> = 0...0.5
}

/// The complete set of mutations available to the CLI, the context menu, and
/// the Claude Code hooks.
enum ControlCommand: Equatable {
    case setColor(scope: ControlScope, tint: PaneTint)
    case clearColor(scope: ControlScope)
    case setName(String)
    case clearName
    /// nil clears the entry, matching a hook session-end.
    case setStatus(ActivityStatus.State?)
    /// App-wide, not scoped to the calling surface's tab or repo.
    case setTintStrength(Double)
    /// What the calling surface types at its prompt on the next restore. nil
    /// clears it.
    case setResumeCommand(String?)
    /// App-wide, like the tint strength.
    case setMinimapVisibility(MinimapVisibility)
    /// The calling surface's tab. nil clears the override, so the tab follows
    /// the app-wide value again.
    case setTabMinimapVisibility(MinimapVisibility?)
    /// App-wide, in points.
    case setMinimapHeight(Double)
    case info
}

enum ControlError: String, Codable, Equatable {
    case unknownSurface = "unknown surface"
    case notInRepo = "surface is not inside a git repository"
}

/// Tints are reported as explicit arrays rather than the compact
/// string-or-array session form, so consumers can index without branching.
struct TintPayload: Codable, Equatable {
    let stops: [String]

    init(_ tint: PaneTint) {
        stops = tint.stops.map(\.text)
    }
}

struct RepoTintPayload: Codable, Equatable {
    let identity: String
    let stops: [String]
}

struct ControlInfo: Codable, Equatable {
    struct Scopes: Codable, Equatable {
        let surface: TintPayload?
        let tab: TintPayload?
        let repo: RepoTintPayload?
    }

    struct Git: Codable, Equatable {
        let repoName: String
        let branch: String?
        let worktree: String?
        let repoPath: String
    }

    /// Both in the CLI text form. `tab` is the tab's override, absent when it
    /// follows the app-wide value.
    struct Minimap: Codable, Equatable {
        let tab: String?
        let effective: String
    }

    let surfaceID: String
    let leafID: String
    let tabID: String
    let tabName: String
    let tabNameIsOverride: Bool
    let scopes: Scopes
    let effective: TintPayload?
    let git: Git?
    let status: String?
    let resumeCommand: String?
    let minimap: Minimap
}

enum ControlResult: Equatable {
    case applied
    case read(ControlInfo)
    case rejected(ControlError)
}
