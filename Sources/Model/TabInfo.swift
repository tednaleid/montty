import Foundation

struct TabInfo: Equatable {
    let displayName: String
    let workingDirectory: String?
    let directoryName: String?      // last path component
    let gitInfo: GitInfo?           // nil if not in a git repo
    let claudeCode: ClaudeCodeStatus?  // nil if Claude Code not detected
    let splitCount: Int             // 1 = no splits
    let minimap: SplitMinimap

    static func from(
        tab: TabProperties,
        gitInfoProvider: (String) -> GitInfo? = GitInfo.from(path:)
    ) -> TabInfo {
        let dirName = tab.workingDirectory.map {
            ($0 as NSString).lastPathComponent
        }

        // Display name: user-set name takes priority.
        // Otherwise show ".../currentDir" (short, scannable).
        // Falls back to autoName or "Terminal".
        let name: String
        if !tab.name.isEmpty {
            name = tab.name
        } else if let pwd = tab.workingDirectory, let dir = dirName {
            let home = NSHomeDirectory()
            if pwd == "/" {
                name = "/"
            } else if pwd == home {
                name = "~"
            } else if pwd == home + "/" + dir {
                // Direct child of home: ~/dirname
                name = "~/\(dir)"
            } else if pwd.hasPrefix(home + "/") {
                name = "\(dir)/"
            } else {
                let parent = (pwd as NSString).deletingLastPathComponent
                name = (parent == "/" || parent.isEmpty) ? "/\(dir)" : "\(dir)/"
            }
        } else if !tab.autoName.isEmpty {
            name = tab.autoName
        } else {
            name = "Terminal"
        }

        let gitInfo: GitInfo? = tab.workingDirectory.flatMap { pwd in
            gitInfoProvider(pwd)
        }

        let claudeCode = TitleParser.claudeCodeStatus(from: tab.autoName)

        let minimap = SplitMinimap.from(
            node: tab.splitRoot, focusedLeafID: tab.focusedLeafID,
            surfaceTitles: tab.surfaceTitles,
            claudeStates: tab.claudeStates,
            surfaceToMonttyID: tab.surfaceToMonttyID
        )

        return TabInfo(
            displayName: name,
            workingDirectory: tab.workingDirectory,
            directoryName: dirName,
            gitInfo: gitInfo,
            claudeCode: claudeCode,
            splitCount: SplitTree.allLeaves(node: tab.splitRoot).count,
            minimap: minimap
        )
    }
}

/// Claude Code status for a terminal pane.
struct ClaudeCodeStatus: Equatable {
    let sessionName: String
    let state: State

    enum State: Equatable {
        case unknown    // detected via title, no hook state yet
        case working    // actively processing (hook: prompt-submit, pre-tool-use)
        case waiting    // needs user input (hook: notification)
        case idle       // finished turn, session still open (hook: stop)
    }
}

/// Minimal subset of Tab properties needed by TabInfo, for testability.
struct TabProperties: Equatable {
    let name: String
    let autoName: String
    let workingDirectory: String?
    let splitRoot: SplitNode
    let focusedLeafID: UUID?
    /// Per-surface terminal titles, keyed by surfaceID.
    var surfaceTitles: [UUID: String] = [:]
    /// Per-surface Claude Code state from hooks, keyed by MONTTY_SURFACE_ID.
    var claudeStates: [String: ClaudeCodeStatus.State] = [:]
    /// Maps Ghostty surfaceID -> MONTTY_SURFACE_ID.
    var surfaceToMonttyID: [UUID: String] = [:]
}
