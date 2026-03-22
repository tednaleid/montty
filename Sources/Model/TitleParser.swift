import Foundation

enum TitleParser {
    /// Extract Claude Code status from a terminal title.
    /// Returns nil if the title is not from Claude Code.
    /// Claude Code titles look like: "Claude Code -- fixing the BCI toggle"
    static func claudeCodeStatus(from title: String) -> ClaudeCodeStatus? {
        let prefix = "Claude Code -- "
        guard title.hasPrefix(prefix) else { return nil }
        let session = String(title.dropFirst(prefix.count))
        guard !session.isEmpty else { return nil }
        return ClaudeCodeStatus(sessionName: session, state: .unknown)
    }
}
