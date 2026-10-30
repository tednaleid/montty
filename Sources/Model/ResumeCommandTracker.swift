// ABOUTME: Applies Claude Code hook events to a surface's resume command: each
// ABOUTME: event names the current session, and a deliberate exit clears it.

import Foundation

/// Applies Claude Code hook events to one surface's resume command.
enum ResumeCommandTracker {
    /// `SessionEnd` reasons that mean the person ended the session on purpose.
    /// `clear` is followed by a `SessionStart` that sets the new session's id.
    /// Any other reason, including none, is Claude dying under a closing
    /// surface or a quitting montty, which must not lose the session.
    static let deliberateEndReasons: Set<String> = ["prompt_input_exit", "logout", "clear"]

    static func apply(_ message: ClaudeHookMessage, to command: inout String?) {
        if message.event == .sessionEnd {
            if let reason = message.reason, deliberateEndReasons.contains(reason) {
                command = nil
            }
            return
        }
        if let sessionID = message.sessionID,
           let resume = ResumeCommand.claude(sessionID: sessionID) {
            command = resume
        }
    }
}
