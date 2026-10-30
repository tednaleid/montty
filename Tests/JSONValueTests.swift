// ABOUTME: Tests for the order-keeping JSON value used to edit Claude Code's
// ABOUTME: settings file: parsing, and writing in Claude's own 2-space format.

import Foundation
import Testing

struct JSONValueTests {
    private let claudeFormatted = """
        {
          "model": "opus",
          "env": {
            "B_FIRST": "1",
            "A_SECOND": "2"
          },
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
          "cleanupPeriodDays": 99999,
          "ratio": 1.50,
          "enabled": true,
          "disabled": false,
          "nothing": null,
          "emptyObject": {},
          "emptyArray": []
        }
        """

    /// U+1D11E, outside the Basic Multilingual Plane, so JSON escapes it as a
    /// surrogate pair.
    private let clef = String(UnicodeScalar(0x1D11E)!)

    @Test func formattedTextRoundTripsExactly() {
        #expect(JSONValue.parse(claudeFormatted)?.formatted() == claudeFormatted)
    }

    @Test func keepsKeyOrder() {
        guard case .object(let members) = JSONValue.parse(#"{"z": 1, "a": 2, "m": 3}"#) else {
            Issue.record("expected an object")
            return
        }
        #expect(members.map(\.key) == ["z", "a", "m"])
    }

    @Test func keepsNumberText() {
        #expect(JSONValue.parse("[1.0, -2e10, 0.25]") == .array([.number("1.0"), .number("-2e10"), .number("0.25")]))
    }

    @Test func decodesStringEscapes() {
        let parsed = JSONValue.parse(#"["a\"b\\c\/d\n\t", "é", "𝄞"]"#)
        #expect(parsed == .array([.string("a\"b\\c/d\n\t"), .string("\u{E9}"), .string(clef)]))
    }

    @Test func writesStringsTheWayClaudeDoes() {
        let value = JSONValue.array([.string("a\"b\\c/d\n\t\u{01}"), .string("\u{E9}" + clef)])
        #expect(value.formatted() == "[\n  \"a\\\"b\\\\c/d\\n\\t\\u0001\",\n  \"\u{E9}\(clef)\"\n]")
    }

    @Test func readsCompactInput() {
        #expect(JSONValue.parse(#"{"a":[1,{"b":null}]}"#) == .object([
            JSONMember(key: "a", value: .array([.number("1"), .object([JSONMember(key: "b", value: .null)])]))
        ]))
    }

    @Test func rejectsInvalidJSON() {
        for bad in ["", "{nope", #"{"a": 1,}"#, "[1, 2] extra", #"{"a" 1}"#, "tru", #""unterminated"#, "01x"] {
            #expect(JSONValue.parse(bad) == nil, "accepted \(bad.debugDescription)")
        }
    }
}
