// ABOUTME: The value a window use case returns instead of performing effects --
// ABOUTME: the shell reads it and does the AppKit work it names.

import Foundation

/// What the shell must do as a result of one decision. Every field defaults to
/// inert, so a use case names only what it wants and the rest is a no-op.
struct WindowOutcome: Equatable {
    /// Windows whose models are already in the registry and now need an NSWindow.
    var createWindows: [WindowPlan] = []
    /// Surfaces to create; the shell reports the ids back via `surfacesCreated`.
    var createSurfaces: [SurfacePlan] = []
    var destroySurfaces: [UUID] = []
    /// Windows to close. Reaching the shell as `NSWindow.close()`, which comes
    /// back as `windowDidClose(id:)`.
    var closeWindows: [UUID] = []
    var raiseWindow: UUID?
    var applySettings: SettingsUpdate?
    var save = false
    var quit = false
}

struct WindowPlan: Equatable {
    let windowID: UUID
    /// A restored frame, or nil to let the shell place the window.
    let frame: WindowFrame?
    /// Offset from this window's on-screen frame. The shell computes the
    /// offset, since only it can read that frame.
    let cascadeFrom: UUID?
}

struct SurfacePlan: Equatable {
    /// The split-tree leaf this surface belongs to. The domain mints leaf ids;
    /// Ghostty mints surface ids, which is why binding them is a second step.
    let leafID: UUID
    let windowID: UUID
    let tabID: UUID
    /// Montty's own id for this surface, exported into the pane's shell as
    /// `MONTTY_SURFACE_ID`; hook events and the control CLI address a surface
    /// by this id, not by `leafID` or the surface id Ghostty mints.
    let monttyID: String
    let workingDirectory: String?
}

/// App-wide settings a restore recovered. They live on the shell, so they cross
/// the boundary as data rather than being written directly.
struct SettingsUpdate: Equatable {
    let surfaceTintEnabled: Bool
    let repoColorOverrides: [String: PaneTint]
}
