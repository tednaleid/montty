// ABOUTME: Which strings are safe to keep as a surface's resume command, which
// ABOUTME: montty types at the surface's prompt when it restores a session.

import Foundation

enum ResumeCommand {
    /// Room for a long command line with arguments; past this the value is not
    /// a command someone typed, and it is re-encoded into every autosave.
    static let maxCharacters = 4096

    /// A resume command is typed at a shell prompt on restore, so it must never
    /// press Enter or send an escape sequence by itself.
    static func isValid(_ command: String) -> Bool {
        !command.isEmpty
            && command.count <= maxCharacters
            && !command.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }

    /// The command that resumes a Claude Code session, or nil when the id holds
    /// anything but letters, digits, `-`, and `_`, so a malformed payload cannot
    /// build a command that does more than resume.
    static func claude(sessionID: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !sessionID.isEmpty,
              sessionID.unicodeScalars.allSatisfy({ $0.isASCII && allowed.contains($0) })
        else { return nil }
        return "claude --resume \(sessionID)"
    }
}
