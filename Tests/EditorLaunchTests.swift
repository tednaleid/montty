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

    /// plan() with both environments injected, so no test depends on the
    /// dotfiles of whoever runs the suite and none spawns a shell.
    private func plan(
        directory: String?,
        own: [String: String] = [:],
        login: [String: String] = [:]
    ) -> EditorLaunch? {
        EditorLaunch.plan(
            directory: directory, ownEnvironment: own, loginEnvironment: { login }
        )
    }

    // MARK: - Nothing to open

    @Test func planIsNilWithoutADirectory() {
        #expect(plan(directory: nil) == nil)
        #expect(plan(directory: "") == nil)
        #expect(plan(directory: "   ") == nil)
    }

    @Test func planIsNilWhenTheDirectoryIsGone() throws {
        let path = try makeDirectory()
        cleanup(path)
        #expect(plan(directory: path) == nil)
    }

    @Test func planIsNilForAFile() throws {
        let dir = try makeDirectory()
        defer { cleanup(dir) }
        let file = (dir as NSString).appendingPathComponent("notes.txt")
        try "x".write(toFile: file, atomically: true, encoding: .utf8)

        #expect(plan(directory: file) == nil)
    }

    // MARK: - Resolution from montty's own environment

    @Test func planUsesOwnVisualWithoutProbing() throws {
        let dir = try makeDirectory()
        defer { cleanup(dir) }
        let own = ["VISUAL": "code", "EDITOR": "vim", "PATH": "/own/bin"]

        var probed = false
        let launch = try #require(EditorLaunch.plan(
            directory: dir, ownEnvironment: own,
            loginEnvironment: {
                probed = true
                return [:]
            }
        ))
        // The probe spawns a shell; it must not run when montty already
        // knows the answer.
        #expect(!probed)
        #expect(launch.executablePath == "/usr/bin/env")
        #expect(launch.arguments == ["code", dir])
        #expect(launch.environment == own)
        #expect(launch.workingDirectory == dir)
    }

    @Test func planFallsBackToOwnEditor() throws {
        let dir = try makeDirectory()
        defer { cleanup(dir) }

        let launch = try #require(
            plan(directory: dir, own: ["EDITOR": "cursor"])
        )
        #expect(launch.arguments == ["cursor", dir])
    }

    // MARK: - Resolution from the login shell

    @Test func planProbesTheLoginShellWhenOwnEnvironmentHasNeither() throws {
        let dir = try makeDirectory()
        defer { cleanup(dir) }
        let login = ["VISUAL": "zed", "EDITOR": "vim", "PATH": "/login/bin"]

        let launch = try #require(
            plan(directory: dir, own: ["PATH": "/own/bin"], login: login)
        )
        // $VISUAL beats $EDITOR here too, and the environment that supplied
        // the editor is the one the child runs under, so the PATH that made
        // "zed" meaningful is the PATH used to find it.
        #expect(launch.arguments == ["zed", dir])
        #expect(launch.environment == login)
    }

    @Test func planTreatsEmptyValuesAsUnset() throws {
        let dir = try makeDirectory()
        defer { cleanup(dir) }

        let launch = try #require(plan(
            directory: dir,
            own: ["VISUAL": "", "EDITOR": "   "],
            login: ["EDITOR": "cursor"]
        ))
        #expect(launch.arguments == ["cursor", dir])
    }

    @Test func planFallsBackToCodeWithTheLoginEnvironment() throws {
        let dir = try makeDirectory()
        defer { cleanup(dir) }
        let login = ["PATH": "/login/bin"]

        let launch = try #require(plan(directory: dir, login: login))
        #expect(launch.arguments == [EditorLaunch.fallbackEditor, dir])
        #expect(launch.environment == login)
    }

    @Test func planKeepsOwnEnvironmentWhenTheProbeFails() throws {
        let dir = try makeDirectory()
        defer { cleanup(dir) }
        let own = ["PATH": "/own/bin"]

        // An empty probe result means the shell failed; stripping the child
        // down to an empty environment would lose even a usable PATH.
        let launch = try #require(plan(directory: dir, own: own, login: [:]))
        #expect(launch.arguments == [EditorLaunch.fallbackEditor, dir])
        #expect(launch.environment == own)
    }

    // MARK: - Argv shape

    @Test func planSplitsFlagsCarriedByTheEditor() throws {
        let dir = try makeDirectory()
        defer { cleanup(dir) }

        // Unsplit, /usr/bin/env would look up a file literally named
        // "code -n --wait" and exit 127.
        let launch = try #require(
            plan(directory: dir, own: ["VISUAL": "code  -n --wait"])
        )
        #expect(launch.arguments == ["code", "-n", "--wait", dir])
    }

    @Test func planPassesTheDirectoryAsItsOwnArgument() throws {
        let dir = try makeDirectory(named: "my project (v2)")
        defer { cleanup(dir) }

        // The directory is appended as one argv entry, never word-split, so
        // spaces and parens in it survive.
        let launch = try #require(plan(directory: dir, own: ["VISUAL": "code -n"]))
        #expect(launch.arguments.last == dir)
    }

    // MARK: - env output parsing

    @Test func parseEnvOutputReadsKeyValueLines() {
        let parsed = EditorLaunch.parseEnvOutput(
            "PATH=/usr/bin:/bin\nEDITOR=code\nLESS=-R --use-color\nEMPTY=\n_UND=x\n"
        )
        #expect(parsed["PATH"] == "/usr/bin:/bin")
        #expect(parsed["EDITOR"] == "code")
        #expect(parsed["LESS"] == "-R --use-color")
        #expect(parsed["EMPTY"] == "")
        #expect(parsed["_UND"] == "x")
    }

    @Test func parseEnvOutputKeepsEqualsSignsInValues() {
        let parsed = EditorLaunch.parseEnvOutput("LS_COLORS=di=34:ln=35\n")
        #expect(parsed["LS_COLORS"] == "di=34:ln=35")
    }

    @Test func parseEnvOutputSkipsLinesThatAreNotAssignments() {
        // Login files are allowed to print: a banner, a line with no "=", a
        // name env(1) could never have produced. None of it may leak into the
        // environment handed to the editor.
        let parsed = EditorLaunch.parseEnvOutput(
            """
            Welcome to this machine!
            2DAY=never
            SPACED NAME=nope
            =bare
            EDITOR=code
            """
        )
        #expect(parsed == ["EDITOR": "code"])
    }
}
