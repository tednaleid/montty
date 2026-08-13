// ABOUTME: Resolves the shell command that opens a directory in the user's editor.
// ABOUTME: Pure value logic -- the shell in Sources/App runs what this describes.

import Foundation

/// The command that opens a directory in the user's editor.
///
/// A GUI app never sources the user's shell startup files, so `$EDITOR` and the
/// `PATH` entry holding `code`/`cursor`/`zed` are both invisible to montty's own
/// environment. Rather than re-derive either, this hands the question to a login
/// zsh and lets it resolve `$VISUAL`, `$EDITOR`, and `PATH`. zsh specifically,
/// not the login shell from the password database: `script` is zsh syntax, and
/// montty's shell integration is already zsh-only.
///
/// Only the login files are read -- `.zshenv`, `.zprofile`, `.zlogin` -- so an
/// `$EDITOR` exported from `.zshrc` alone is not visible here. That is the cost
/// of not running an interactive shell, and it is worth paying: `.zshrc` is
/// written on the assumption that the shell owns a terminal, and a config that
/// sets up zle aborts startup when there isn't one, leaving the editor
/// unlaunched. `.zshenv` is the correct home for an exported variable anyway.
///
/// The editor is expected to be a GUI one that returns immediately. A terminal
/// editor named in `$EDITOR` (`nvim`, `vim`) gets no tty here and exits at once;
/// opening one in a pane would be a different feature.
struct EditorLaunch: Equatable {
    let executablePath: String
    let arguments: [String]
    let workingDirectory: String

    /// Editor used when neither `$VISUAL` nor `$EDITOR` is set.
    static let fallbackEditor = "code"

    /// `$VISUAL` before `$EDITOR` because `$EDITOR` is conventionally the
    /// terminal editor and this launch has no terminal to give it.
    ///
    /// `${=cmd}` is zsh's explicit word split. zsh does not split unquoted
    /// parameters the way other shells do, so without it an `$EDITOR` carrying
    /// flags (`code -n`) is passed as one argv entry and fails to exec. The
    /// directory arrives as `"$@"` rather than spliced into the text, so spaces
    /// in it never reach the parser.
    static let script = """
        cmd=${VISUAL:-${EDITOR:-\(Self.fallbackEditor)}}; exec ${=cmd} "$@"
        """

    /// The launch that opens `directory`, or nil when there is nothing to open.
    ///
    /// A pane reports no directory until its shell emits OSC 7, and a pane whose
    /// directory has since been deleted would hand the editor a path that is not
    /// there, so both answer nil rather than launching onto nothing.
    static func plan(directory: String?) -> EditorLaunch? {
        guard let directory,
              !directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: directory, isDirectory: &isDirectory
        ), isDirectory.boolValue else { return nil }

        return EditorLaunch(
            executablePath: "/bin/zsh",
            // A login shell, deliberately not an interactive one. -i would also
            // read .zshrc, but .zshrc is written for a shell that owns a
            // terminal: a real config that touches zle aborts the startup here
            // and the editor never launches. Login mode reads .zshenv,
            // .zprofile, and .zlogin, which is where an exported $EDITOR
            // belongs and where the PATH holding `code` comes from.
            // "montty" is $0, leaving the directory as $1 for "$@".
            arguments: ["-l", "-c", script, "montty", directory],
            workingDirectory: directory
        )
    }
}
