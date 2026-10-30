// ABOUTME: montty's hook entries for Claude Code's settings file: syncing and
// ABOUTME: removing them, the hooks version check, and which sessions report.

import Foundation

enum ClaudeHooks {
    /// The version of the installed entries, separate from montty's release
    /// version. Raise it whenever `events` or `command(for:)` changes, so
    /// sessions running older entries are told to reinstall. Entries written
    /// before versioning carry no version and count as 1.
    static let version = 2

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
        "[ -z \"$MONTTY_BIN\" ] || \(monttyMarker)\(hookArgument) --hooks-version \(version)"
    }

    private static let monttyMarker = "\"$MONTTY_BIN\" hook "

    private static func group(for hookArgument: String) -> JSONValue {
        .object([JSONMember(key: "hooks", value: .array([.object([
            JSONMember(key: "type", value: .string("command")),
            JSONMember(key: "command", value: .string(command(for: hookArgument)))
        ])]))])
    }

    private static func isMontty(_ hook: JSONValue) -> Bool {
        guard case .string(let command)? = hook["command"] else { return false }
        return command.contains(monttyMarker)
    }

    private static func commands(in group: JSONValue) -> [JSONValue] {
        guard case .array(let hooks)? = group["hooks"] else { return [] }
        return hooks
    }

    /// One event's groups with montty's commands removed, dropping each group
    /// that held nothing else.
    private static func withoutMontty(_ groups: [JSONValue]) -> [JSONValue] {
        groups.compactMap { group -> JSONValue? in
            let hooks = commands(in: group)
            let others = hooks.filter { !isMontty($0) }
            if others.count == hooks.count { return group }
            return others.isEmpty ? nil : group.setting("hooks", to: .array(others))
        }
    }

    /// An event's value with montty's commands removed, or nil when no group
    /// is left. A value that is not an array is not montty's and is kept.
    private static func withoutMontty(_ value: JSONValue) -> JSONValue? {
        guard case .array(let groups) = value else { return value }
        let kept = withoutMontty(groups)
        return kept.isEmpty ? nil : .array(kept)
    }

    /// Brings montty's entries to the current set: an event already holding
    /// exactly the current entry is left where it is, any other montty entry
    /// is replaced, and montty entries for events no longer used are removed.
    static func installing(into settings: JSONValue) -> JSONValue {
        guard case .object(let existing) = settings["hooks"] ?? .object([]) else { return settings }
        var hooks = JSONValue.object(existing)
        for member in existing where !events.contains(where: { $0.claudeEvent == member.key }) {
            hooks = hooks.setting(member.key, to: withoutMontty(member.value))
        }
        for (claudeEvent, hookArgument) in events {
            let desired = group(for: hookArgument)
            guard case .array(let groups) = hooks[claudeEvent] ?? .array([]) else { continue }
            let monttyCount = groups.flatMap(commands(in:)).filter(isMontty).count
            if monttyCount == 1 && groups.contains(desired) { continue }
            hooks = hooks.setting(claudeEvent, to: .array(withoutMontty(groups) + [desired]))
        }
        return settings.setting("hooks", to: hooks)
    }

    /// Removes montty's commands, then any group, event, or `hooks` key that
    /// held nothing else.
    static func uninstalling(from settings: JSONValue) -> JSONValue {
        guard case .object(let existing)? = settings["hooks"] else { return settings }
        var hooks = JSONValue.object(existing)
        for member in existing {
            hooks = hooks.setting(member.key, to: withoutMontty(member.value))
        }
        if hooks == settings["hooks"] { return settings }
        return settings.setting("hooks", to: hooks == .object([]) ? nil : hooks)
    }

    /// What `montty hook session-start` prints for Claude: a message shown to
    /// the user when the installed entries are older than this montty's, or nil.
    static func sessionStartReply(installedVersion: Int?) -> String? {
        let installed = installedVersion ?? 1
        guard installed < version else { return nil }
        let message = "montty: Claude Code hooks are out of date (version \(installed), "
            + "this montty uses \(version)). Run `montty install-hooks claude` to update."
        return JSONValue.object([JSONMember(key: "systemMessage", value: .string(message))]).formatted()
    }

    /// Interactive Claude sessions report `cli`. Headless runs (`claude -p`, the
    /// SDK) report something else even when started from an interactive
    /// session's shell, so a script or an agent's tool call in the surface
    /// cannot take over its indicator or resume command.
    static func reportsSession(entrypoint: String?) -> Bool {
        entrypoint == nil || entrypoint == "cli"
    }
}
