// ABOUTME: Tests for adding montty's hooks to Claude Code's settings and removing
// ABOUTME: them, and for which Claude sessions report to montty.

import Foundation
import Testing

struct ClaudeHooksTests {
    private func json(_ settings: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "<invalid>"
    }

    private func commands(_ settings: [String: Any], event: String) -> [String] {
        let groups = (settings["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    private let userHook: [String: Any] = [
        "hooks": [
            "PreToolUse": [
                ["matcher": "Bash", "hooks": [["type": "command", "command": "veer check"]]]
            ]
        ],
        "model": "opus"
    ]

    // MARK: - Install

    @Test func installAddsOneCommandPerEvent() {
        let installed = ClaudeHooks.installing(into: [:])
        let expected: [(String, String)] = [
            ("SessionStart", "session-start"),
            ("UserPromptSubmit", "prompt-submit"),
            ("PreToolUse", "pre-tool-use"),
            ("Notification", "notification"),
            ("Stop", "stop"),
            ("SessionEnd", "session-end")
        ]
        for (event, argument) in expected {
            #expect(
                commands(installed, event: event) == ["[ -z \"$MONTTY_BIN\" ] || \"$MONTTY_BIN\" hook \(argument)"],
                "for \(event)"
            )
        }
    }

    @Test func installKeepsUserHooksAndSettings() {
        let installed = ClaudeHooks.installing(into: userHook)
        #expect(commands(installed, event: "PreToolUse").first == "veer check")
        #expect(commands(installed, event: "PreToolUse").count == 2)
        #expect(installed["model"] as? String == "opus")
    }

    @Test func installTwiceChangesNothing() {
        let once = ClaudeHooks.installing(into: userHook)
        #expect(json(ClaudeHooks.installing(into: once)) == json(once))
    }

    // MARK: - Uninstall

    @Test func uninstallRestoresOriginalSettings() {
        let installed = ClaudeHooks.installing(into: userHook)
        #expect(json(ClaudeHooks.uninstalling(from: installed)) == json(userHook))
    }

    @Test func uninstallDropsEmptyHooksKey() {
        let installed = ClaudeHooks.installing(into: ["model": "opus"])
        #expect(json(ClaudeHooks.uninstalling(from: installed)) == json(["model": "opus"]))
    }

    @Test func uninstallWithoutMonttyHooksChangesNothing() {
        #expect(json(ClaudeHooks.uninstalling(from: userHook)) == json(userHook))
    }

    @Test func uninstallKeepsUserCommandSharingAGroup() {
        let shared: [String: Any] = [
            "hooks": [
                "Stop": [
                    ["hooks": [
                        ["type": "command", "command": "say done"],
                        ["type": "command", "command": "[ -z \"$MONTTY_BIN\" ] || \"$MONTTY_BIN\" hook stop"]
                    ]]
                ]
            ]
        ]
        #expect(commands(ClaudeHooks.uninstalling(from: shared), event: "Stop") == ["say done"])
    }

    // MARK: - Which sessions report

    @Test func interactiveSessionsReport() {
        #expect(ClaudeHooks.reportsSession(entrypoint: "cli"))
    }

    @Test func sessionWithoutEntrypointReports() {
        #expect(ClaudeHooks.reportsSession(entrypoint: nil))
    }

    @Test func headlessSessionsDoNotReport() {
        #expect(!ClaudeHooks.reportsSession(entrypoint: "sdk-cli"))
        #expect(!ClaudeHooks.reportsSession(entrypoint: "sdk-ts"))
    }
}
