import Testing
@testable import montty_unit

struct TitleParserTests {
    @Test func detectsClaudeCodeTitle() {
        let status = TitleParser.claudeCodeStatus(from: "Claude Code -- fixing BCI")
        #expect(status != nil)
        #expect(status?.sessionName == "fixing BCI")
        #expect(status?.state == .unknown)
    }

    @Test func detectsClaudeCodeWithLongName() {
        let status = TitleParser.claudeCodeStatus(
            from: "Claude Code -- refactoring the auth middleware for compliance"
        )
        #expect(status?.sessionName == "refactoring the auth middleware for compliance")
    }

    @Test func returnsNilForShellTitle() {
        #expect(TitleParser.claudeCodeStatus(from: "zsh") == nil)
    }

    @Test func returnsNilForEmptyTitle() {
        #expect(TitleParser.claudeCodeStatus(from: "") == nil)
    }

    @Test func returnsNilForPartialPrefix() {
        #expect(TitleParser.claudeCodeStatus(from: "Claude Code") == nil)
    }

    @Test func returnsNilForPlainCommand() {
        #expect(TitleParser.claudeCodeStatus(from: "vim main.swift") == nil)
    }
}
