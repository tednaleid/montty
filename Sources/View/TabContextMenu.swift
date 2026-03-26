import SwiftUI

struct TabContextMenu: View {
    let tab: Tab
    var repoColorOverrides: [String: TabColor] = [:]
    let onRename: () -> Void
    let onSetRepoColor: (String, TabColor?) -> Void
    let onSetTabColor: (TabColor?) -> Void
    let onClose: () -> Void

    /// The focused surface's directory, if any.
    private var focusedDir: String? {
        tab.focusedSurfaceID.flatMap { tab.surfaceDirectories[$0] }
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
        guard let info = focusedGitInfo else { return "Color" }
        if let worktree = info.worktreeName {
            return "Color: \(info.repoName) (\(worktree))"
        }
        return "Color: \(info.repoName)"
    }

    var body: some View {
        Button("Rename...") { onRename() }

        // Repo/worktree color (affects minimap and other tabs with this repo)
        if let identity = repoIdentity {
            let repoColor = TabColor.colorForWorktree(
                focusedDir, overrides: repoColorOverrides
            ) ?? .gray
            let hasRepoOverride = repoColorOverrides[identity] != nil
            Menu(repoColorLabel) {
                TabColorPicker(
                    currentColor: repoColor,
                    hasOverride: hasRepoOverride,
                    onSelect: { color in onSetRepoColor(identity, color) }
                )
            }
        }

        // Tab-level color override (affects tab bar and surface borders)
        let tabOverride = tab.colorOverride
        Menu("Tab Color") {
            TabColorPicker(
                currentColor: tabOverride ?? tab.effectiveColor(overrides: repoColorOverrides),
                hasOverride: tabOverride != nil,
                onSelect: { color in onSetTabColor(color) }
            )
        }

        Divider()

        Button("Close Tab") { onClose() }
    }
}
