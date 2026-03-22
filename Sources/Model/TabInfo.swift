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
        let name = tab.name.isEmpty ? tab.autoName : tab.name
        let dirName = tab.workingDirectory.map {
            ($0 as NSString).lastPathComponent
        }

        let gitInfo: GitInfo? = tab.workingDirectory.flatMap { pwd in
            gitInfoProvider(pwd)
        }

        let claudeCode = TitleParser.claudeCodeStatus(from: tab.autoName)

        let minimap = SplitMinimap.from(
            node: tab.splitRoot, focusedLeafID: tab.focusedLeafID
        )

        return TabInfo(
            displayName: name.isEmpty ? "Terminal" : name,
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
        case unknown    // detected Claude Code, can't determine state yet
        case working    // actively processing (future signal)
        case waiting    // needs user input (future signal)
    }
}

/// Minimal subset of Tab properties needed by TabInfo, for testability.
struct TabProperties: Equatable {
    let name: String
    let autoName: String
    let workingDirectory: String?
    let splitRoot: SplitNode
    let focusedLeafID: UUID?
}
