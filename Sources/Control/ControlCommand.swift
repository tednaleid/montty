// ABOUTME: The driving port: every mutation an outside actor can ask montty
// ABOUTME: for, plus the result and info payload those actors read back.

import Foundation

/// Which layer of the color precedence a command targets.
enum ControlScope: String, Codable, CaseIterable {
    case surface, tab, repo
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

    let surfaceID: String
    let leafID: String
    let tabID: String
    let tabName: String
    let tabNameIsOverride: Bool
    let scopes: Scopes
    let effective: TintPayload?
    let git: Git?
    let status: String?
}

enum ControlResult: Equatable {
    case applied
    case read(ControlInfo)
    case rejected(ControlError)
}
