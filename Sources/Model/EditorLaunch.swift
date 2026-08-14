// ABOUTME: Resolves the command that opens a directory in the user's editor.
// ABOUTME: Checks the filesystem and can probe a login shell; Sources/App runs the result.

import Foundation

/// The command that opens a directory in the user's editor.
///
/// A GUI app launched from the Dock never sources the user's shell startup
/// files, so `$VISUAL`, `$EDITOR`, and the `PATH` entry holding `code`/`cursor`
/// can all be invisible to montty's own environment. Resolution order, first
/// environment with a non-empty value wins:
///
/// 1. montty's own environment -- free, and already correct whenever montty
///    was started from a terminal.
/// 2. a login-shell probe: `$SHELL -l -c env`, so the user's actual shell
///    (zsh, bash, fish -- all of which montty ships integration for) answers
///    with its own login files. Login, deliberately not interactive: an
///    interactive shell is allowed to do work (`fish -i` can rewrite config
///    files during a version migration), and a keystroke should not. The cost
///    is that a variable exported only from `.zshrc`/`.bashrc` is not seen.
/// 3. `code`.
///
/// Whichever environment supplied the editor also becomes the child's
/// environment, so the `PATH` that made the value meaningful is the one used
/// to resolve it. `/usr/bin/env` performs that lookup, which means a missing
/// editor surfaces as exit 127 for the caller to beep on instead of vanishing.
///
/// The editor is expected to be a GUI one that returns immediately. A terminal
/// editor named in `$EDITOR` (`nvim`, `vim`) gets no tty here and exits at
/// once; opening one in a pane would be a different feature.
struct EditorLaunch: Equatable {
    let executablePath: String
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: String

    /// Editor used when neither `$VISUAL` nor `$EDITOR` is set anywhere.
    static let fallbackEditor = "code"

    /// The launch that opens `directory`, or nil when there is nothing to open.
    ///
    /// A pane reports no directory until its shell emits OSC 7, and a pane
    /// whose directory has since been deleted would hand the editor a path
    /// that is not there, so both answer nil rather than launching onto
    /// nothing.
    ///
    /// `loginEnvironment` is only invoked when `ownEnvironment` holds no
    /// editor, so the subprocess cost is not paid when montty already knows
    /// the answer.
    static func plan(
        directory: String?,
        ownEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        loginEnvironment: () -> [String: String] = probeLoginEnvironment
    ) -> EditorLaunch? {
        guard let directory,
              !directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: directory, isDirectory: &isDirectory
        ), isDirectory.boolValue else { return nil }

        let editor: String
        let environment: [String: String]
        if let own = editorValue(in: ownEnvironment) {
            editor = own
            environment = ownEnvironment
        } else {
            let login = loginEnvironment()
            editor = editorValue(in: login) ?? fallbackEditor
            // An empty probe result (shell missing, exited nonzero) would strip
            // the child of even a default PATH; montty's own environment is the
            // better bad option.
            environment = login.isEmpty ? ownEnvironment : login
        }

        return EditorLaunch(
            executablePath: "/usr/bin/env",
            // Split so an editor value carrying flags ("code -n") becomes
            // separate argv entries. The directory is appended as its own
            // entry, never parsed, so spaces in it survive. A quoted editor
            // path containing a space does not survive this split -- same
            // limitation the previous zsh ${=cmd} split had.
            arguments: editor.split(separator: " ").map(String.init) + [directory],
            environment: environment,
            workingDirectory: directory
        )
    }

    /// `$VISUAL` before `$EDITOR`: `$EDITOR` is conventionally the terminal
    /// editor and this launch has no terminal to give it. Empty and
    /// whitespace-only values count as unset.
    private static func editorValue(in environment: [String: String]) -> String? {
        for key in ["VISUAL", "EDITOR"] {
            if let value = environment[key],
               !value.trimmingCharacters(in: .whitespaces).isEmpty {
                return value
            }
        }
        return nil
    }

    // MARK: - Login environment probe

    /// The environment the user's login shell would provide: `$SHELL -l -c
    /// env`. `env` is a real binary, so no shell syntax is involved and zsh,
    /// bash, and fish all run it the same way. Returns empty on any failure
    /// so the caller can fall back to montty's own environment.
    static func probeLoginEnvironment() -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: loginShell())
        process.arguments = ["-l", "-c", "env"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return [:]
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(bytes: data, encoding: .utf8)
        else { return [:] }
        return parseEnvOutput(output)
    }

    /// The user's shell from montty's environment, falling back to the
    /// password database the way login(1) would.
    private static func loginShell() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"],
           !shell.isEmpty {
            return shell
        }
        if let passwd = getpwuid(getuid()), let shell = passwd.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty { return path }
        }
        return "/bin/zsh"
    }

    /// `env` prints one KEY=VALUE per line. Lines that do not begin with a
    /// legal variable name are skipped: login files are allowed to print to
    /// stdout, and a value that itself contains a newline spills onto lines
    /// of its own. Skipping keeps the noise out at the cost of truncating
    /// such a value at its first newline.
    static func parseEnvOutput(_ output: String) -> [String: String] {
        var environment: [String: String] = [:]
        for line in output.split(separator: "\n") {
            guard let separator = line.firstIndex(of: "="),
                  isVariableName(line[..<separator])
            else { continue }
            environment[String(line[..<separator])] =
                String(line[line.index(after: separator)...])
        }
        return environment
    }

    private static func isVariableName(_ name: Substring) -> Bool {
        guard let first = name.first,
              first == "_" || first.isASCII && first.isLetter
        else { return false }
        return name.dropFirst().allSatisfy {
            $0 == "_" || $0.isASCII && ($0.isLetter || $0.isNumber)
        }
    }
}
