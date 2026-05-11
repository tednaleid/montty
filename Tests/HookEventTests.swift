import Foundation
import Testing

struct HookEventTests {
    // MARK: - Message parsing

    @Test func parsesSessionStart() {
        let msg = ClaudeHookMessage.parse(
            json: "{\"event\":\"session-start\",\"surface\":\"abc-123\"}"
        )
        #expect(msg == ClaudeHookMessage(event: .sessionStart, surface: "abc-123"))
    }

    @Test func parsesAllEvents() {
        let cases: [(String, ClaudeHookEvent)] = [
            ("session-start", .sessionStart),
            ("prompt-submit", .promptSubmit),
            ("pre-tool-use", .preToolUse),
            ("notification", .notification),
            ("stop", .stop),
            ("session-end", .sessionEnd)
        ]
        for (raw, expected) in cases {
            let msg = ClaudeHookMessage.parse(
                json: "{\"event\":\"\(raw)\",\"surface\":\"s1\"}"
            )
            #expect(msg?.event == expected, "expected \(expected) for \(raw)")
        }
    }

    @Test func rejectsUnknownEvent() {
        let msg = ClaudeHookMessage.parse(
            json: "{\"event\":\"bogus\",\"surface\":\"s1\"}"
        )
        #expect(msg == nil)
    }

    @Test func rejectsMissingFields() {
        #expect(ClaudeHookMessage.parse(json: "{\"event\":\"stop\"}") == nil)
        #expect(ClaudeHookMessage.parse(json: "{\"surface\":\"s1\"}") == nil)
        #expect(ClaudeHookMessage.parse(json: "{}") == nil)
    }

    @Test func rejectsEmptySurface() {
        let msg = ClaudeHookMessage.parse(
            json: "{\"event\":\"stop\",\"surface\":\"\"}"
        )
        #expect(msg == nil)
    }

    @Test func rejectsMalformedJSON() {
        #expect(ClaudeHookMessage.parse(json: "not json") == nil)
        #expect(ClaudeHookMessage.parse(json: "") == nil)
    }

    // MARK: - cwd field

    @Test func parsesCwdWhenPresent() {
        let msg = ClaudeHookMessage.parse(
            json: "{\"event\":\"session-start\",\"surface\":\"s1\",\"cwd\":\"/Users/me/proj\"}"
        )
        #expect(msg?.cwd == "/Users/me/proj")
    }

    @Test func cwdAbsentParsesAsNil() {
        // Backward compat: pre-fix wrappers don't send cwd. Message must still parse.
        let msg = ClaudeHookMessage.parse(
            json: "{\"event\":\"stop\",\"surface\":\"s1\"}"
        )
        #expect(msg != nil)
        #expect(msg?.cwd == nil)
    }

    @Test func emptyCwdParsesAsNil() {
        let msg = ClaudeHookMessage.parse(
            json: "{\"event\":\"stop\",\"surface\":\"s1\",\"cwd\":\"\"}"
        )
        #expect(msg?.cwd == nil)
    }

    // MARK: - Directory tracker

    @Test func trackerRecordsCwdOnSessionStart() {
        var dirs: [String: String] = [:]
        HookDirectoryTracker.apply(
            event: .sessionStart, surfaceID: "s1",
            cwd: "/path/to/worktree", to: &dirs
        )
        #expect(dirs["s1"] == "/path/to/worktree")
    }

    @Test func trackerUpdatesCwdOnPreToolUse() {
        var dirs: [String: String] = ["s1": "/old"]
        HookDirectoryTracker.apply(
            event: .preToolUse, surfaceID: "s1",
            cwd: "/new", to: &dirs
        )
        #expect(dirs["s1"] == "/new")
    }

    @Test func trackerClearsCwdOnSessionEnd() {
        var dirs: [String: String] = ["s1": "/path", "s2": "/other"]
        HookDirectoryTracker.apply(
            event: .sessionEnd, surfaceID: "s1",
            cwd: nil, to: &dirs
        )
        #expect(dirs["s1"] == nil)
        #expect(dirs["s2"] == "/other")
    }

    @Test func trackerLeavesExistingValueWhenCwdMissing() {
        var dirs: [String: String] = ["s1": "/old"]
        HookDirectoryTracker.apply(
            event: .notification, surfaceID: "s1",
            cwd: nil, to: &dirs
        )
        #expect(dirs["s1"] == "/old")
    }

    @Test func trackerIgnoresEmptyCwd() {
        var dirs: [String: String] = ["s1": "/old"]
        HookDirectoryTracker.apply(
            event: .notification, surfaceID: "s1",
            cwd: "", to: &dirs
        )
        #expect(dirs["s1"] == "/old")
    }

    // MARK: - State machine

    @Test func sessionStartSetsIdle() {
        var states: [String: ClaudeCodeStatus.State] = [:]
        var waitingSince: [String: Date] = [:]
        let outcome = HookStateMachine.apply(
            .sessionStart, surfaceID: "s1",
            to: &states, waitingSince: &waitingSince, isKnownSurface: true
        )
        #expect(outcome == .applied(newState: .idle))
        #expect(states["s1"] == .idle)
        #expect(waitingSince["s1"] == nil)
    }

    @Test func promptSubmitSetsWorking() {
        var states: [String: ClaudeCodeStatus.State] = [:]
        var waitingSince: [String: Date] = [:]
        _ = HookStateMachine.apply(
            .promptSubmit, surfaceID: "s1",
            to: &states, waitingSince: &waitingSince, isKnownSurface: true
        )
        #expect(states["s1"] == .working)
    }

    @Test func preToolUseSetsWorking() {
        var states: [String: ClaudeCodeStatus.State] = [:]
        var waitingSince: [String: Date] = [:]
        _ = HookStateMachine.apply(
            .preToolUse, surfaceID: "s1",
            to: &states, waitingSince: &waitingSince, isKnownSurface: true
        )
        #expect(states["s1"] == .working)
    }

    @Test func preToolUseClearsStaleWaiting() {
        // Root-cause scenario: Claude was in .waiting (permission dialog),
        // user approved via UI, Claude resumes via tool use -> .working.
        var states: [String: ClaudeCodeStatus.State] = ["s1": .waiting]
        var waitingSince: [String: Date] = ["s1": Date(timeIntervalSince1970: 100)]
        let outcome = HookStateMachine.apply(
            .preToolUse, surfaceID: "s1",
            to: &states, waitingSince: &waitingSince, isKnownSurface: true
        )
        #expect(outcome == .applied(newState: .working))
        #expect(states["s1"] == .working)
        #expect(waitingSince["s1"] == nil)  // cleared
    }

    @Test func notificationSetsWaiting() {
        var states: [String: ClaudeCodeStatus.State] = [:]
        var waitingSince: [String: Date] = [:]
        let now = Date(timeIntervalSince1970: 500)
        _ = HookStateMachine.apply(
            .notification, surfaceID: "s1",
            to: &states, waitingSince: &waitingSince, isKnownSurface: true, now: now
        )
        #expect(states["s1"] == .waiting)
        #expect(waitingSince["s1"] == now)
    }

    @Test func stopSetsIdleAndClearsWaitingSince() {
        var states: [String: ClaudeCodeStatus.State] = ["s1": .waiting]
        var waitingSince: [String: Date] = ["s1": Date()]
        _ = HookStateMachine.apply(
            .stop, surfaceID: "s1",
            to: &states, waitingSince: &waitingSince, isKnownSurface: true
        )
        #expect(states["s1"] == .idle)
        #expect(waitingSince["s1"] == nil)
    }

    @Test func sessionEndRemovesEntry() {
        var states: [String: ClaudeCodeStatus.State] = ["s1": .working]
        var waitingSince: [String: Date] = [:]
        let outcome = HookStateMachine.apply(
            .sessionEnd, surfaceID: "s1",
            to: &states, waitingSince: &waitingSince, isKnownSurface: true
        )
        #expect(outcome == .applied(newState: nil))
        #expect(states["s1"] == nil)
    }

    @Test func sessionEndClearsWaitingSince() {
        var states: [String: ClaudeCodeStatus.State] = ["s1": .waiting]
        var waitingSince: [String: Date] = ["s1": Date()]
        _ = HookStateMachine.apply(
            .sessionEnd, surfaceID: "s1",
            to: &states, waitingSince: &waitingSince, isKnownSurface: true
        )
        #expect(states["s1"] == nil)
        #expect(waitingSince["s1"] == nil)
    }

    @Test func staleSurfaceIDRejected() {
        var states: [String: ClaudeCodeStatus.State] = ["s1": .idle]
        var waitingSince: [String: Date] = [:]
        let outcome = HookStateMachine.apply(
            .notification, surfaceID: "unknown",
            to: &states, waitingSince: &waitingSince, isKnownSurface: false
        )
        #expect(outcome == .rejectedUnknownSurface)
        #expect(states["unknown"] == nil)   // no mutation
        #expect(states["s1"] == .idle)       // unrelated entry untouched
    }
}
