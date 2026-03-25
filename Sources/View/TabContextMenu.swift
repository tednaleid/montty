import SwiftUI

struct TabContextMenu: View {
    let tab: Tab
    var repoColorOverrides: [String: TabColor] = [:]
    let onRename: () -> Void
    let onSetRepoColor: (String, TabColor?) -> Void
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

    /// Display label for the color menu (repo name, optionally with worktree).
    private var colorMenuLabel: String {
        guard let info = focusedGitInfo else { return "Color" }
        if let worktree = info.worktreeName {
            return "Color: \(info.repoName) (\(worktree))"
        }
        return "Color: \(info.repoName)"
    }

    var body: some View {
        Button("Rename...") { onRename() }

        // Only show color menu when focused surface is in a git repo
        if let identity = repoIdentity {
            let currentColor = tab.effectiveColor(overrides: repoColorOverrides)
            Menu(colorMenuLabel) {
                TabColorPicker(
                    currentColor: currentColor,
                    onSelect: { color in
                        onSetRepoColor(identity, color)
                    }
                )
            }
        }

        Divider()

        Button("Close Tab") { onClose() }
    }
}
