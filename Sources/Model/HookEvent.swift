// ABOUTME: Pure state machine for Claude Code hook events. Parses JSON hook
// ABOUTME: messages and applies state transitions to per-surface Claude state.

import Foundation

/// Events fired by Claude Code hooks and routed to montty via Unix socket.
enum ClaudeHookEvent: String {
    case sessionStart = "session-start"
    case promptSubmit = "prompt-submit"
    case preToolUse = "pre-tool-use"
    case notification
    case stop
    case sessionEnd = "session-end"
}

/// A parsed hook message.
struct ClaudeHookMessage: Equatable {
    let event: ClaudeHookEvent
    let surface: String
    /// The cwd Claude Code reported on stdin. Optional for backward compat with
    /// older wrappers; the worktree color tracking depends on it being present.
    let cwd: String?

    init(event: ClaudeHookEvent, surface: String, cwd: String? = nil) {
        self.event = event
        self.surface = surface
        self.cwd = cwd
    }

    /// Parse a hook message body. Expects: {"event": "<name>", "surface": "<id>", "cwd": "<path>"?}.
    /// Returns nil for malformed JSON, unknown events, or missing fields.
    static func parse(json: String) -> ClaudeHookMessage? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventStr = obj["event"] as? String,
              let event = ClaudeHookEvent(rawValue: eventStr),
              let surface = obj["surface"] as? String,
              !surface.isEmpty else {
            return nil
        }
        let rawCwd = obj["cwd"] as? String
        let cwd = (rawCwd?.isEmpty ?? true) ? nil : rawCwd
        return ClaudeHookMessage(event: event, surface: surface, cwd: cwd)
    }
}

/// Pure logic for tracking Claude-reported cwd per surface. Kept separate from
/// HookStateMachine because cwd isn't part of the state transition.
enum HookDirectoryTracker {
    /// Apply a hook event's cwd update to the directories dict.
    /// - `session-end` removes the entry.
    /// - Any other event with a non-empty cwd updates the entry.
    /// - A nil/empty cwd on a non-end event is a no-op (preserves prior value).
    static func apply(
        event: ClaudeHookEvent,
        surfaceID: String,
        cwd: String?,
        to directories: inout [String: String]
    ) {
        if event == .sessionEnd {
            directories.removeValue(forKey: surfaceID)
            return
        }
        if let cwd, !cwd.isEmpty {
            directories[surfaceID] = cwd
        }
    }
}

/// Pure state transition logic for Claude hook events.
/// Extracted from HookServer so it can be unit-tested.
enum HookStateMachine {
    /// Result of applying an event.
    enum Outcome: Equatable {
        case applied(newState: ClaudeCodeStatus.State?)  // nil means entry removed (session-end)
        case rejectedUnknownSurface
    }

    /// Apply a hook event to the given state dicts in place.
    /// - `isKnownSurface` must be true, or the update is rejected without mutation.
    /// - `waitingSince` tracks when a surface entered `.waiting` (for timeout sweep).
    /// - Returns `.applied` with the new state, or `.rejectedUnknownSurface`.
    static func apply(
        _ event: ClaudeHookEvent,
        surfaceID: String,
        to claudeStates: inout [String: ClaudeCodeStatus.State],
        waitingSince: inout [String: Date],
        isKnownSurface: Bool,
        now: Date = Date()
    ) -> Outcome {
        guard isKnownSurface else { return .rejectedUnknownSurface }

        switch event {
        case .sessionStart:
            claudeStates[surfaceID] = .idle
            waitingSince.removeValue(forKey: surfaceID)
            return .applied(newState: .idle)
        case .promptSubmit, .preToolUse:
            claudeStates[surfaceID] = .working
            waitingSince.removeValue(forKey: surfaceID)
            return .applied(newState: .working)
        case .notification:
            claudeStates[surfaceID] = .waiting
            waitingSince[surfaceID] = now
            return .applied(newState: .waiting)
        case .stop:
            claudeStates[surfaceID] = .idle
            waitingSince.removeValue(forKey: surfaceID)
            return .applied(newState: .idle)
        case .sessionEnd:
            claudeStates.removeValue(forKey: surfaceID)
            waitingSince.removeValue(forKey: surfaceID)
            return .applied(newState: nil)
        }
    }
}
