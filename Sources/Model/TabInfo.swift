// ABOUTME: Computes what the sidebar shows for a tab: name, directory, git info, split count.
// ABOUTME: TabProperties is the subset of Tab state it reads, so it is testable alone.
import Foundation

struct TabInfo: Equatable {
    let displayName: String
    /// The name the tab shows when neither it nor its focused surface has one.
    let autoDisplayName: String
    let workingDirectory: String?
    let directoryName: String?      // last path component
    let gitInfo: GitInfo?           // nil if not in a git repo
    let splitCount: Int             // 1 = no splits
    let minimap: SplitMinimap

    /// The Claude status of the tab as a whole: its most urgent pane's, or nil
    /// when no pane has a session reporting in.
    var activity: ActivityStatus.State? {
        ActivityStatus.State.mostUrgent(of: minimap.panes.compactMap { $0.activity?.state })
    }

    static func from(
        tab: TabProperties,
        gitInfoProvider: (String) -> GitInfo? = GitInfo.from(path:)
    ) -> TabInfo {
        let focusedSurfaceID: UUID? = tab.focusedLeafID.flatMap { leafID in
            SplitTree.allLeaves(node: tab.splitRoot)
                .first { $0.id == leafID }?.surfaceID
        }
        // Use the focused surface's directory
        let focusedDir: String? = focusedSurfaceID.flatMap { tab.surfaceDirectories[$0] }

        let dirName = focusedDir.map {
            ($0 as NSString).lastPathComponent
        }

        // The automatic name is "dirname/" (short, scannable), falling back
        // to autoName or "Terminal".
        let auto: String
        if let pwd = focusedDir, let dir = dirName {
            let home = NSHomeDirectory()
            if pwd == "/" {
                auto = "/"
            } else if pwd == home {
                auto = "~"
            } else if pwd == home + "/" + dir {
                // Direct child of home: ~/dirname
                auto = "~/\(dir)"
            } else if pwd.hasPrefix(home + "/") {
                auto = "\(dir)/"
            } else {
                let parent = (pwd as NSString).deletingLastPathComponent
                auto = (parent == "/" || parent.isEmpty) ? "/\(dir)" : "\(dir)/"
            }
        } else if !tab.autoName.isEmpty {
            auto = tab.autoName
        } else {
            auto = "Terminal"
        }

        // The focused surface's name takes priority, then the tab's.
        let named = focusedSurfaceID.flatMap { tab.surfaceNames[$0] } ?? tab.name
        let name = named.isEmpty ? auto : named

        let gitInfo: GitInfo? = focusedDir.flatMap { pwd in
            gitInfoProvider(pwd)
        }

        let minimap = SplitMinimap.from(
            node: tab.splitRoot, focusedLeafID: tab.focusedLeafID,
            surfaceTitles: tab.surfaceTitles,
            activityStates: tab.activityStates,
            surfaceToMonttyID: tab.surfaceToMonttyID
        )

        return TabInfo(
            displayName: name,
            autoDisplayName: auto,
            workingDirectory: focusedDir,
            directoryName: dirName,
            gitInfo: gitInfo,
            splitCount: SplitTree.allLeaves(node: tab.splitRoot).count,
            minimap: minimap
        )
    }
}

/// Minimal subset of Tab properties needed by TabInfo, for testability.
struct TabProperties: Equatable {
    let name: String
    let autoName: String
    let splitRoot: SplitNode
    let focusedLeafID: UUID?
    /// Per-surface working directories, keyed by surfaceID.
    var surfaceDirectories: [UUID: String] = [:]
    /// Per-surface terminal titles, keyed by surfaceID.
    var surfaceTitles: [UUID: String] = [:]
    /// Per-surface activity state populated by hook events, keyed by MONTTY_SURFACE_ID.
    var activityStates: [String: ActivityStatus.State] = [:]
    /// Maps Ghostty surfaceID -> MONTTY_SURFACE_ID.
    var surfaceToMonttyID: [UUID: String] = [:]
    /// Per-surface name, keyed by surfaceID.
    var surfaceNames: [UUID: String] = [:]
}
