// ABOUTME: montty's hook entries for Claude Code's settings file: adding them,
// ABOUTME: removing them, and which Claude sessions report to montty.

import Foundation

enum ClaudeHooks {
    /// Each Claude Code hook event montty listens to, paired with the
    /// `montty hook` argument it reports as.
    static let events: [(claudeEvent: String, hookArgument: String)] = [
        ("SessionStart", "session-start"),
        ("UserPromptSubmit", "prompt-submit"),
        ("PreToolUse", "pre-tool-use"),
        ("Notification", "notification"),
        ("Stop", "stop"),
        ("SessionEnd", "session-end")
    ]

    /// Every montty surface sets MONTTY_BIN to the running app's binary, so the
    /// command reports to whichever montty owns the surface and does nothing
    /// in any other terminal.
    static func command(for hookArgument: String) -> String {
        "[ -z \"$MONTTY_BIN\" ] || \(monttyMarker)\(hookArgument)"
    }

    private static let monttyMarker = "\"$MONTTY_BIN\" hook "

    private static func isMontty(_ hook: [String: Any]) -> Bool {
        (hook["command"] as? String)?.contains(monttyMarker) == true
    }

    static func installing(into settings: [String: Any]) -> [String: Any] {
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (claudeEvent, hookArgument) in events {
            var groups = hooks[claudeEvent] as? [[String: Any]] ?? []
            let present = groups.contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains(where: isMontty)
            }
            if !present {
                groups.append(["hooks": [["type": "command", "command": command(for: hookArgument)]]])
            }
            hooks[claudeEvent] = groups
        }
        var result = settings
        result["hooks"] = hooks
        return result
    }

    /// Removes montty's commands, then any group, event, or `hooks` key that
    /// held nothing else.
    static func uninstalling(from settings: [String: Any]) -> [String: Any] {
        guard let hooks = settings["hooks"] as? [String: Any] else { return settings }
        var remaining: [String: Any] = [:]
        for (claudeEvent, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                remaining[claudeEvent] = value
                continue
            }
            let kept = groups.compactMap { group -> [String: Any]? in
                guard let commands = group["hooks"] as? [[String: Any]] else { return group }
                let others = commands.filter { !isMontty($0) }
                if others.isEmpty { return nil }
                var trimmed = group
                trimmed["hooks"] = others
                return trimmed
            }
            if !kept.isEmpty { remaining[claudeEvent] = kept }
        }
        var result = settings
        result["hooks"] = remaining.isEmpty ? nil : remaining
        return result
    }

    /// Interactive Claude sessions report `cli`. Headless runs (`claude -p`, the
    /// SDK) report something else even when started from an interactive
    /// session's shell, so a script or an agent's tool call in the surface
    /// cannot take over its indicator or resume command.
    static func reportsSession(entrypoint: String?) -> Bool {
        entrypoint == nil || entrypoint == "cli"
    }
}
