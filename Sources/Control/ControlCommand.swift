// ABOUTME: The driving port: every mutation an outside actor can ask montty
// ABOUTME: for, plus the result and info payload those actors read back.

import Foundation

/// Which layer of the color precedence a command targets.
enum ControlScope: String, Codable, CaseIterable {
    case surface, tab, repo
}

/// Whose value a setting holds, narrowest first. A narrower scope's value
/// overrides a wider one.
enum SettingScope: String, CaseIterable {
    case surface, tab, repo, app
}

/// The settings the CLI can set, reset, and read, under their CLI names.
enum SettingName: String {
    case color
    case name
    case status
    case resumeCommand = "resume-command"
    case surfaceTintStrength = "surface-tint-strength"
    case tabTintStrength = "tab-tint-strength"
    case minimap
    case minimapHeight = "minimap-height"

    /// The key this setting is reported under in the `settings` object of
    /// `montty info`.
    var infoKey: String {
        rawValue.replacingOccurrences(of: "-", with: "_")
    }
}

/// A request to print what a setting resolves to at a scope.
struct SettingRead: Equatable {
    let setting: SettingName
    let scope: SettingScope
}

/// The settings held at the app scope.
struct AppSettings: Equatable {
    var surfaceTintStrength = SurfaceTintStrength.default
    var tabTintStrength = TabTintStrength.default
    var minimapVisibility = MinimapVisibility.always
    var minimapHeight = MinimapHeight.default
}

/// Opacity of the surface tint overlay.
enum SurfaceTintStrength {
    static let `default`: Double = 0.12
    /// 0 hides the tint entirely. Capped at 0.5, not 1: the overlay is a flat
    /// fill, so opacity 1 replaces every pixel and hides the pane's content
    /// completely rather than just tinting it.
    static let range: ClosedRange<Double> = 0...0.5
}

/// Strength of the tint wash behind a tab in the sidebar.
enum TabTintStrength {
    static let `default`: Double = 0.12
    /// 0 turns the wash off. The top of the range is where the strongest row,
    /// the active one with its minimap hidden, becomes fully opaque.
    static let range: ClosedRange<Double> = 0...0.3

    /// The opacity of one row's wash. `base` is the strength of a row that is
    /// not active and shows its minimap. The active row is stronger so it
    /// stays distinct, and a row with its minimap hidden is stronger again
    /// because it has no minimap rectangle to carry the tint.
    static func opacity(base: Double, isActive: Bool, showsMinimap: Bool) -> Double {
        let factor: Double
        switch (isActive, showsMinimap) {
        case (false, true): factor = 1
        case (true, true): factor = 1.25
        case (false, false): factor = 5.0 / 3
        case (true, false): factor = 10.0 / 3
        }
        return min(base * factor, 1)
    }
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
    /// The surface tint strength at the app scope.
    case setTintStrength(Double)
    /// What the calling surface types at its prompt on the next restore. nil
    /// clears it.
    case setResumeCommand(String?)
    /// The minimap visibility at the app scope.
    case setMinimapVisibility(MinimapVisibility)
    /// The calling surface's tab. nil clears the override, so the tab follows
    /// the app value again.
    case setTabMinimapVisibility(MinimapVisibility?)
    /// The minimap height at the app scope, in points.
    case setMinimapHeight(Double)
    /// The tab tint strength at the app scope.
    case setTabTintStrength(Double)
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

    /// One setting's value at each scope that has one, and what the calling
    /// surface resolves to. A scope with no value of its own is absent.
    struct Scoped<Value: Codable & Equatable>: Codable, Equatable {
        let surface: Value?
        let tab: Value?
        let repo: Value?
        let app: Value?
        let effective: Value

        init(
            surface: Value? = nil, tab: Value? = nil, repo: Value? = nil,
            app: Value? = nil, effective: Value
        ) {
            self.surface = surface
            self.tab = tab
            self.repo = repo
            self.app = app
            self.effective = effective
        }
    }

    /// `minimap` is in the CLI text form.
    struct Settings: Codable, Equatable {
        let surfaceTintStrength: Scoped<Double>
        let tabTintStrength: Scoped<Double>
        let minimap: Scoped<String>
        let minimapHeight: Scoped<Double>
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
    let settings: Settings
}

enum ControlResult: Equatable {
    case applied
    case read(ControlInfo)
    case rejected(ControlError)
}
