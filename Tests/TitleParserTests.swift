import Testing
@testable import montty_unit

struct TitleParserTests {
    // MARK: - Claude Code detection via ✳ prefix

    @Test func detectsClaudeCodeStartup() {
        let status = TitleParser.claudeCodeStatus(from: "✳ Claude Code")
        #expect(status != nil)
        #expect(status?.sessionName == "Claude Code")
        #expect(status?.state == .unknown)
    }

    @Test func detectsClaudeCodeTaskDescription() {
        let status = TitleParser.claudeCodeStatus(
            from: "✳ Determine user name and favorite color"
        )
        #expect(status != nil)
        #expect(status?.sessionName == "Determine user name and favorite color")
    }

    @Test func detectsClaudeCodeShortTask() {
        let status = TitleParser.claudeCodeStatus(from: "✳ Fix auth bug")
        #expect(status?.sessionName == "Fix auth bug")
    }

    @Test func returnsNilForShellTitle() {
        #expect(TitleParser.claudeCodeStatus(from: "zsh") == nil)
    }

    @Test func returnsNilForEmptyTitle() {
        #expect(TitleParser.claudeCodeStatus(from: "") == nil)
    }

    @Test func returnsNilForPlainCommand() {
        #expect(TitleParser.claudeCodeStatus(from: "vim main.swift") == nil)
    }

    @Test func returnsNilForPathTitle() {
        #expect(TitleParser.claudeCodeStatus(from: ".../workspace/montty") == nil)
    }

    @Test func returnsNilForStarAlone() {
        #expect(TitleParser.claudeCodeStatus(from: "✳") == nil)
    }

    @Test func returnsNilForStarWithOnlySpace() {
        #expect(TitleParser.claudeCodeStatus(from: "✳ ") == nil)
    }
}
