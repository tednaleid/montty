// ABOUTME: Tests for a surface's resume command: which strings are safe to type
// ABOUTME: at a prompt, and how Claude hook events set and clear it.

import Foundation
import Testing

struct ResumeCommandTests {
    // MARK: - Validation

    @Test func acceptsOrdinaryCommand() {
        #expect(ResumeCommand.isValid("nvim -S 'my session.vim'"))
    }

    @Test func rejectsEmptyCommand() {
        #expect(!ResumeCommand.isValid(""))
    }

    @Test func rejectsControlCharacters() {
        for bad in ["ls\n", "ls\r", "a\u{1B}[0m", "a\u{00}b", "a\tb", "a\u{7F}"] {
            #expect(!ResumeCommand.isValid(bad), "accepted \(bad.debugDescription)")
        }
    }

    @Test func acceptsCommandAtLengthCap() {
        #expect(ResumeCommand.isValid(String(repeating: "a", count: ResumeCommand.maxCharacters)))
    }

    @Test func rejectsCommandPastLengthCap() {
        #expect(!ResumeCommand.isValid(String(repeating: "a", count: ResumeCommand.maxCharacters + 1)))
    }

    // MARK: - Claude command

    @Test func buildsClaudeResumeCommand() {
        #expect(
            ResumeCommand.claude(sessionID: "0b4c2f1e-9d3a-4c55-8a3e-2f1d6e7b8c90")
                == "claude --resume 0b4c2f1e-9d3a-4c55-8a3e-2f1d6e7b8c90"
        )
    }

    @Test func refusesSessionIDThatIsNotPlainIdentifier() {
        for bad in ["abc; rm -rf ~", "abc\n", "$(whoami)", "a b", ""] {
            #expect(ResumeCommand.claude(sessionID: bad) == nil, "built from \(bad.debugDescription)")
        }
    }

    // MARK: - Tracker

    @Test func everyEventWithSessionIDSetsCommand() {
        for event in [ClaudeHookEvent.sessionStart, .promptSubmit, .preToolUse, .notification, .stop] {
            var command: String?
            ResumeCommandTracker.apply(
                ClaudeHookMessage(event: event, surface: "s1", sessionID: "abc"),
                to: &command
            )
            #expect(command == "claude --resume abc", "for \(event)")
        }
    }

    @Test func laterSessionIDReplacesEarlierOne() {
        var command: String? = "claude --resume before-branch"
        ResumeCommandTracker.apply(
            ClaudeHookMessage(event: .promptSubmit, surface: "s1", sessionID: "after-branch"),
            to: &command
        )
        #expect(command == "claude --resume after-branch")
    }

    @Test func claudeSessionReplacesHandSetCommand() {
        var command: String? = "nvim -S session.vim"
        ResumeCommandTracker.apply(
            ClaudeHookMessage(event: .sessionStart, surface: "s1", sessionID: "abc"),
            to: &command
        )
        #expect(command == "claude --resume abc")
    }

    @Test func eventWithoutSessionIDLeavesCommand() {
        var command: String? = "claude --resume abc"
        ResumeCommandTracker.apply(
            ClaudeHookMessage(event: .stop, surface: "s1"),
            to: &command
        )
        #expect(command == "claude --resume abc")
    }

    @Test func unsafeSessionIDLeavesCommand() {
        var command: String? = "claude --resume abc"
        ResumeCommandTracker.apply(
            ClaudeHookMessage(event: .stop, surface: "s1", sessionID: "x\nrm -rf ~"),
            to: &command
        )
        #expect(command == "claude --resume abc")
    }

    @Test func deliberateSessionEndClearsCommand() {
        for reason in ["prompt_input_exit", "logout", "clear"] {
            var command: String? = "claude --resume abc"
            ResumeCommandTracker.apply(
                ClaudeHookMessage(event: .sessionEnd, surface: "s1", sessionID: "abc", reason: reason),
                to: &command
            )
            #expect(command == nil, "for reason \(reason)")
        }
    }

    @Test func otherSessionEndKeepsCommand() {
        for reason: String? in ["other", "bypass_permissions_disabled", nil] {
            var command: String? = "claude --resume abc"
            ResumeCommandTracker.apply(
                ClaudeHookMessage(event: .sessionEnd, surface: "s1", sessionID: "abc", reason: reason),
                to: &command
            )
            #expect(command == "claude --resume abc", "for reason \(reason ?? "nil")")
        }
    }
}
