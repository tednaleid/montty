// ABOUTME: A request to open a new tab: where it opens, what it is called, what it runs,
// ABOUTME: and the pure checks and path resolution that make the request safe to act on.

import Foundation

/// What `montty tab new` asks for. A tab opens in the window of the pane that
/// asked, behind whatever is in front unless `focus` says otherwise, so a
/// session that spawns tabs does not pull the user off the one they are in.
struct NewTab: Equatable {
    /// Where the tab's shell starts. Absolute once it crosses the socket; nil
    /// inherits the directory of the pane that asked.
    var directory: String?
    var name: String?
    /// What the new shell runs, the program first and then its arguments.
    /// Empty opens a plain shell.
    var command: [String] = []
    var focus = false

    /// Room for a long brief with pasted context, counted across the program
    /// and every argument. The cap is about sanity, not about fitting.
    static let maxCommandCharacters = 100_000

    /// A command is handed to the new shell's `montty launch` as arguments,
    /// which cannot hold a NUL byte and must name a program to run.
    static func isValidCommand(_ command: [String]) -> Bool {
        command.first?.isEmpty != true
            && command.reduce(0) { $0 + $1.count } <= maxCommandCharacters
            && !command.contains { $0.unicodeScalars.contains { $0.value == 0 } }
    }

    /// What a surface opened with a command types and runs. The line is the
    /// same for every command: text typed into a terminal acts on control
    /// characters as they arrive, before a shell reads any quoting, so the
    /// command itself is never typed. `montty launch` asks the app for it.
    static let launchLine = "\"$MONTTY_BIN\" launch"

    /// A tab's directory is handed to the new shell as a working directory, so it
    /// must be a plain absolute path.
    static func isValidDirectory(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }

    /// The same request with `directory` made absolute against the directory the
    /// caller ran from, which only the CLI knows -- the app's own is unrelated.
    /// `~` is the home directory, and `.` and `..` are resolved.
    func resolvingDirectory(cwd: String, home: String) -> NewTab {
        guard let raw = directory else { return self }
        var resolved = self
        resolved.directory = Self.absolute(raw, cwd: cwd, home: home)
        return resolved
    }

    private static func absolute(_ raw: String, cwd: String, home: String) -> String {
        let joined: String
        if raw == "~" {
            joined = home
        } else if raw.hasPrefix("~/") {
            joined = home + "/" + raw.dropFirst(2)
        } else if raw.hasPrefix("/") {
            joined = raw
        } else {
            joined = cwd + "/" + raw
        }
        var parts: [Substring] = []
        for part in joined.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { _ = parts.popLast(); continue }
            parts.append(part)
        }
        return "/" + parts.joined(separator: "/")
    }
}
