// ABOUTME: Tests for syncing montty's hooks into Claude Code's settings and
// ABOUTME: removing them, the hooks version check, and which sessions report.

import Foundation
import Testing

struct ClaudeHooksTests {
    private func settings(_ text: String) -> JSONValue {
        guard let value = JSONValue.parse(text) else {
            Issue.record("fixture is not JSON: \(text)")
            return .object([])
        }
        return value
    }

    private func commands(_ settings: JSONValue, event: String) -> [String] {
        guard case .array(let groups)? = settings["hooks"]?[event] else { return [] }
        return groups.flatMap { group -> [String] in
            guard case .array(let hooks)? = group["hooks"] else { return [] }
            return hooks.compactMap { hook in
                guard case .string(let command)? = hook["command"] else { return nil }
                return command
            }
        }
    }

    private func monttyCommand(_ argument: String) -> String {
        "[ -z \"$MONTTY_BIN\" ] || \"$MONTTY_BIN\" hook \(argument) --hooks-version \(ClaudeHooks.version)"
    }

    private let userSettings = """
        {
          "model": "opus",
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  {
                    "type": "command",
                    "command": "veer check"
                  }
                ]
              }
            ]
          },
          "cleanupPeriodDays": 99999
        }
        """

    // MARK: - Install

    @Test func installAddsOneCommandPerEvent() {
        let installed = ClaudeHooks.installing(into: .object([]))
        let expected: [(String, String)] = [
            ("SessionStart", "session-start"),
            ("UserPromptSubmit", "prompt-submit"),
            ("PreToolUse", "pre-tool-use"),
            ("Notification", "notification"),
            ("Stop", "stop"),
            ("SessionEnd", "session-end")
        ]
        for (event, argument) in expected {
            #expect(commands(installed, event: event) == [monttyCommand(argument)], "for \(event)")
        }
    }

    @Test func installKeepsUserHooksSettingsAndKeyOrder() {
        let installed = ClaudeHooks.installing(into: settings(userSettings))
        #expect(commands(installed, event: "PreToolUse") == ["veer check", monttyCommand("pre-tool-use")])
        guard case .object(let members) = installed else {
            Issue.record("expected an object")
            return
        }
        #expect(members.map(\.key) == ["model", "hooks", "cleanupPeriodDays"])
    }

    @Test func installTwiceChangesNothing() {
        let once = ClaudeHooks.installing(into: settings(userSettings))
        #expect(ClaudeHooks.installing(into: once) == once)
    }

    @Test func installReplacesEntriesFromAnEarlierVersion() {
        let earlier = settings("""
            {"hooks": {
              "Stop": [{"hooks": [{"type": "command",
                "command": "[ -z \\"$MONTTY_BIN\\" ] || \\"$MONTTY_BIN\\" hook stop"}]}],
              "PostToolUse": [{"hooks": [{"type": "command", "command": "\\"$MONTTY_BIN\\" hook post-tool-use"}]}]
            }}
            """)
        let installed = ClaudeHooks.installing(into: earlier)
        #expect(commands(installed, event: "Stop") == [monttyCommand("stop")])
        #expect(installed["hooks"]?["PostToolUse"] == nil)
    }

    @Test func installLeavesCurrentEntriesWhereTheyAre() {
        let current = ClaudeHooks.installing(into: .object([]))
        guard case .array(var stop)? = current["hooks"]?["Stop"] else {
            Issue.record("expected Stop groups")
            return
        }
        stop.append(settings(#"{"hooks": [{"type": "command", "command": "say done"}]}"#))
        let withUserHookAfter = current.setting("hooks", to: current["hooks"]!.setting("Stop", to: .array(stop)))
        #expect(ClaudeHooks.installing(into: withUserHookAfter) == withUserHookAfter)
    }

    // MARK: - Uninstall

    @Test func uninstallRestoresOriginalTextExactly() {
        let installed = ClaudeHooks.installing(into: settings(userSettings))
        #expect(ClaudeHooks.uninstalling(from: installed).formatted() == userSettings)
    }

    @Test func uninstallDropsEmptyHooksKey() {
        let installed = ClaudeHooks.installing(into: settings(#"{"model": "opus"}"#))
        #expect(ClaudeHooks.uninstalling(from: installed) == settings(#"{"model": "opus"}"#))
    }

    @Test func uninstallWithoutMonttyHooksChangesNothing() {
        #expect(ClaudeHooks.uninstalling(from: settings(userSettings)) == settings(userSettings))
    }

    @Test func uninstallKeepsUserCommandSharingAGroup() {
        let shared = settings("""
            {"hooks": {"Stop": [{"hooks": [
              {"type": "command", "command": "say done"},
              {"type": "command", "command": "[ -z \\"$MONTTY_BIN\\" ] || \\"$MONTTY_BIN\\" hook stop"}
            ]}]}}
            """)
        #expect(commands(ClaudeHooks.uninstalling(from: shared), event: "Stop") == ["say done"])
    }

    // MARK: - Hooks version check

    @Test func entriesWithoutAVersionAreOutOfDate() {
        #expect(ClaudeHooks.sessionStartReply(installedVersion: nil) != nil)
    }

    @Test func olderEntriesGetASystemMessage() {
        let reply = ClaudeHooks.sessionStartReply(installedVersion: ClaudeHooks.version - 1)
        guard case .string(let message)? = reply.flatMap(JSONValue.parse)?["systemMessage"] else {
            Issue.record("expected a systemMessage, got \(reply ?? "nil")")
            return
        }
        #expect(message.contains("montty install-hooks claude"))
    }

    @Test func currentOrNewerEntriesSayNothing() {
        #expect(ClaudeHooks.sessionStartReply(installedVersion: ClaudeHooks.version) == nil)
        #expect(ClaudeHooks.sessionStartReply(installedVersion: ClaudeHooks.version + 1) == nil)
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
