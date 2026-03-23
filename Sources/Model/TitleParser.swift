import Foundation

enum TitleParser {
    /// Extract Claude Code status from a terminal title.
    /// Claude Code sets the title to "✳ <description>" when active.
    /// Returns nil if the title is not from Claude Code.
    static func claudeCodeStatus(from title: String) -> ClaudeCodeStatus? {
        let prefix = "✳ "
        guard title.hasPrefix(prefix) else { return nil }
        let session = String(title.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespaces)
        guard !session.isEmpty else { return nil }
        return ClaudeCodeStatus(sessionName: session, state: .unknown)
    }
}
