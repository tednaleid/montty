import SwiftUI

struct TabContextMenu: View {
    let tab: Tab
    var repoColorOverrides: [String: PaneTint] = [:]
    let onRename: () -> Void
    let onControl: (ControlCommand) -> Void
    let onClose: () -> Void

    /// The focused surface's directory, if any. Prefers Claude-reported cwd
    /// over the parent shell's pwd so the menu reflects the active worktree.
    private var focusedDir: String? {
        tab.focusedSurfaceID.flatMap { tab.effectiveSurfaceDirectories[$0] }
    }

    /// Git info for the focused surface.
    private var focusedGitInfo: GitInfo? {
        focusedDir.flatMap { GitInfo.from(path: $0) }
    }

    /// Repo identity string for the focused surface (used as override key).
    private var repoIdentity: String? {
        guard let info = focusedGitInfo else { return nil }
        return info.repoPath + (info.worktreeName ?? "")
    }

    /// Display label for the repo color menu.
    private var repoColorLabel: String {
        guard let info = focusedGitInfo else { return "Repo Color" }
        if let worktree = info.worktreeName {
            return "Repo Color: \(info.repoName) (\(worktree))"
        }
        return "Repo Color: \(info.repoName)"
    }

    private var surfaceOverride: PaneTint? {
        tab.focusedSurfaceID.flatMap { tab.surfaceColorOverrides[$0] }
    }

    /// The swatch to check in a submenu, or nil to check none. A missing
    /// override falls back to the effective color for that scope; a gradient
    /// or hex override matches no named swatch, so only Reset applies.
    private func swatch(for override: PaneTint?, fallback: TintStop) -> TintStop? {
        guard let override else { return fallback }
        guard !override.isGradient, case .named = override.primary else { return nil }
        return override.primary
    }

    var body: some View {
        Button("Rename...") { onRename() }

        Menu("Surface Color") {
            TabColorPicker(
                currentColor: swatch(
                    for: surfaceOverride,
                    fallback: tab.effectiveColor(overrides: repoColorOverrides)
                ),
                hasOverride: surfaceOverride != nil,
                onSelect: { tint in
                    onControl(tint.map { .setColor(scope: .surface, tint: $0) }
                        ?? .clearColor(scope: .surface))
                }
            )
        }

        Menu("Tab Color") {
            TabColorPicker(
                currentColor: swatch(
                    for: tab.colorOverride,
                    fallback: tab.effectiveColor(overrides: repoColorOverrides)
                ),
                hasOverride: tab.colorOverride != nil,
                onSelect: { tint in
                    onControl(tint.map { .setColor(scope: .tab, tint: $0) }
                        ?? .clearColor(scope: .tab))
                }
            )
        }

        if let identity = repoIdentity {
            let override = repoColorOverrides[identity]
            Menu(repoColorLabel) {
                TabColorPicker(
                    currentColor: swatch(
                        for: override,
                        fallback: .named(TabColor.colorForWorktree(focusedDir) ?? .gray)
                    ),
                    hasOverride: override != nil,
                    onSelect: { tint in
                        onControl(tint.map { .setColor(scope: .repo, tint: $0) }
                            ?? .clearColor(scope: .repo))
                    }
                )
            }
        }

        Divider()

        Button("Close Tab") { onClose() }
    }
}
