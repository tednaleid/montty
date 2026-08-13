import Foundation
import Testing
@testable import montty_unit

struct EditorLaunchTests {
    // MARK: - Helpers

    /// A directory that exists for the duration of one test.
    private func makeDirectory(named name: String = "workspace") throws -> String {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent(
            "montty-test-\(UUID().uuidString)/\(name)"
        )
        try FileManager.default.createDirectory(
            atPath: path, withIntermediateDirectories: true
        )
        return path
    }

    private func cleanup(_ path: String) {
        let components = path.split(separator: "/")
        if let testIdx = components.firstIndex(where: { $0.hasPrefix("montty-test-") }) {
            let root = "/" + components[...testIdx].joined(separator: "/")
            try? FileManager.default.removeItem(atPath: root)
        }
    }

    /// Run the production script under a controlled environment and return what
    /// the resolved editor printed.
    ///
    /// `-f` skips startup files so the result depends on `env` alone rather than
    /// on the dotfiles of whoever runs the suite. The real launch needs `-l`
    /// for exactly the opposite reason; the script text under test is the same.
    private func runScript(env: [String: String], directory: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-f", "-c", EditorLaunch.script, "montty", directory]
        process.environment = env
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(bytes: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A directory holding an executable named `code` that echoes its arguments,
    /// so the fallback can be observed without a real editor installed.
    private func makeFakeEditorPath() throws -> String {
        let dir = try makeDirectory(named: "bin")
        let code = (dir as NSString).appendingPathComponent(EditorLaunch.fallbackEditor)
        try "#!/bin/sh\necho fallback \"$@\"\n".write(
            toFile: code, atomically: true, encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: code
        )
        return dir
    }

    // MARK: - Planning

    @Test func planIsNilWithoutADirectory() {
        #expect(EditorLaunch.plan(directory: nil) == nil)
        #expect(EditorLaunch.plan(directory: "") == nil)
        #expect(EditorLaunch.plan(directory: "   ") == nil)
    }

    @Test func planIsNilWhenTheDirectoryIsGone() throws {
        let path = try makeDirectory()
        cleanup(path)
        #expect(EditorLaunch.plan(directory: path) == nil)
    }

    @Test func planIsNilForAFile() throws {
        let dir = try makeDirectory()
        defer { cleanup(dir) }
        let file = (dir as NSString).appendingPathComponent("notes.txt")
        try "x".write(toFile: file, atomically: true, encoding: .utf8)

        #expect(EditorLaunch.plan(directory: file) == nil)
    }

    @Test func planRunsTheScriptInTheDirectory() throws {
        let dir = try makeDirectory()
        defer { cleanup(dir) }

        let launch = try #require(EditorLaunch.plan(directory: dir))
        #expect(launch.executablePath == "/bin/zsh")
        #expect(launch.workingDirectory == dir)
        #expect(launch.arguments.last == dir)
        #expect(launch.arguments.contains(EditorLaunch.script))
    }

    @Test func planUsesALoginButNotInteractiveShell() throws {
        let dir = try makeDirectory()
        defer { cleanup(dir) }

        let launch = try #require(EditorLaunch.plan(directory: dir))
        // -l reads the login files that export $EDITOR and build PATH. -i is
        // deliberately absent: a real .zshrc that sets up zle aborts startup
        // when the shell has no terminal, and the editor never launches.
        #expect(launch.arguments.contains("-l"))
        #expect(!launch.arguments.contains("-i"))
    }

    @Test func planPassesTheDirectoryAsAnArgument() throws {
        let dir = try makeDirectory(named: "my project (v2)")
        defer { cleanup(dir) }

        let launch = try #require(EditorLaunch.plan(directory: dir))
        // Spliced into the script text, a directory like this would be parsed
        // as several words; as its own argv entry it survives intact.
        #expect(!EditorLaunch.script.contains(dir))
        #expect(launch.arguments.last == dir)
    }

    // MARK: - Script behavior

    @Test func scriptOpensTheDirectoryInVisual() throws {
        let dir = try makeDirectory()
        defer { cleanup(dir) }

        let output = try runScript(env: ["VISUAL": "/bin/echo visual"], directory: dir)
        #expect(output == "visual \(dir)")
    }

    @Test func scriptFallsBackToEditor() throws {
        let dir = try makeDirectory()
        defer { cleanup(dir) }

        let output = try runScript(env: ["EDITOR": "/bin/echo editor"], directory: dir)
        #expect(output == "editor \(dir)")
    }

    @Test func scriptPrefersVisualOverEditor() throws {
        let dir = try makeDirectory()
        defer { cleanup(dir) }

        let output = try runScript(
            env: ["VISUAL": "/bin/echo visual", "EDITOR": "/bin/echo editor"],
            directory: dir
        )
        #expect(output == "visual \(dir)")
    }

    @Test func scriptTreatsAnEmptyEditorAsUnset() throws {
        let dir = try makeDirectory()
        defer { cleanup(dir) }
        let bin = try makeFakeEditorPath()
        defer { cleanup(bin) }

        let output = try runScript(
            env: ["VISUAL": "", "EDITOR": "", "PATH": bin], directory: dir
        )
        #expect(output == "fallback \(dir)")
    }

    @Test func scriptUsesTheFallbackEditorWhenNeitherIsSet() throws {
        let dir = try makeDirectory()
        defer { cleanup(dir) }
        let bin = try makeFakeEditorPath()
        defer { cleanup(bin) }

        let output = try runScript(env: ["PATH": bin], directory: dir)
        #expect(output == "fallback \(dir)")
    }

    @Test func scriptSplitsFlagsCarriedByTheEditor() throws {
        let dir = try makeDirectory()
        defer { cleanup(dir) }

        // Without zsh's ${=cmd} split this execs a file literally named
        // "/bin/echo --new-window" and prints nothing.
        let output = try runScript(
            env: ["VISUAL": "/bin/echo --new-window"], directory: dir
        )
        #expect(output == "--new-window \(dir)")
    }
}
