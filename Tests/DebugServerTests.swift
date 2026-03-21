#if DEBUG

import Foundation
import Testing

// These tests verify the pure functions used by DebugServer.
// The functions are duplicated here because DebugServer.swift has Ghostty
// dependencies that can't be linked into the standalone test target.
// If the implementations drift, the integration tests (just inspect-*) will catch it.

struct DebugServerParsingTests {

    // Mirrors DebugServer.parseRequest
    struct HTTPRequest {
        var method: String
        var path: String
        var query: [String: String]
        var body: String
    }

    static func parseRequest(_ data: Data) -> HTTPRequest {
        let raw = String(data: data, encoding: .utf8) ?? ""
        let lines = raw.split(separator: "\r\n", omittingEmptySubsequences: false)

        var method = "GET"
        var fullPath = "/"
        if let requestLine = lines.first {
            let parts = requestLine.split(separator: " ", maxSplits: 2)
            if parts.count >= 2 {
                method = String(parts[0])
                fullPath = String(parts[1])
            }
        }

        var path = fullPath
        var query: [String: String] = [:]
        if let qIndex = fullPath.firstIndex(of: "?") {
            path = String(fullPath[fullPath.startIndex..<qIndex])
            let queryString = String(fullPath[fullPath.index(after: qIndex)...])
            for param in queryString.split(separator: "&") {
                let keyValue = param.split(separator: "=", maxSplits: 1)
                if keyValue.count == 2 {
                    let key = String(keyValue[0]).removingPercentEncoding ?? String(keyValue[0])
                    let value = String(keyValue[1]).removingPercentEncoding ?? String(keyValue[1])
                    query[key] = value
                }
            }
        }

        var body = ""
        if let blankLineIndex = lines.firstIndex(of: "") {
            let bodyLines = lines[(blankLineIndex + 1)...]
            body = bodyLines.joined(separator: "\r\n")
        }

        return HTTPRequest(method: method, path: path, query: query, body: body)
    }

    @Test func parseSimpleGet() {
        let raw = "GET /surfaces HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let request = Self.parseRequest(Data(raw.utf8))
        #expect(request.method == "GET")
        #expect(request.path == "/surfaces")
        #expect(request.query.isEmpty)
        #expect(request.body.isEmpty)
    }

    @Test func parseGetWithQueryParams() {
        let raw = "GET /screen?surface=ABC-123 HTTP/1.1\r\n\r\n"
        let request = Self.parseRequest(Data(raw.utf8))
        #expect(request.method == "GET")
        #expect(request.path == "/screen")
        #expect(request.query["surface"] == "ABC-123")
    }

    @Test func parsePostWithBody() {
        let raw = "POST /type HTTP/1.1\r\nContent-Length: 10\r\n\r\necho hello"
        let request = Self.parseRequest(Data(raw.utf8))
        #expect(request.method == "POST")
        #expect(request.path == "/type")
        #expect(request.body == "echo hello")
    }

    @Test func parsePercentEncodedQuery() {
        let raw = "GET /state?surface=A%20B HTTP/1.1\r\n\r\n"
        let request = Self.parseRequest(Data(raw.utf8))
        #expect(request.query["surface"] == "A B")
    }
}

struct DebugServerKeyMappingTests {

    // Mirrors DebugServer.keyToText
    // swiftlint:disable:next cyclomatic_complexity
    static func keyToText(_ name: String) -> String? {
        switch name.lowercased() {
        case "return", "enter":     return "\r"
        case "tab":                 return "\t"
        case "space":               return " "
        case "escape", "esc":       return "\u{1B}"
        case "backspace", "delete": return "\u{7F}"
        case "ctrl+c":              return "\u{03}"
        case "ctrl+d":              return "\u{04}"
        case "ctrl+z":              return "\u{1A}"
        case "ctrl+l":              return "\u{0C}"
        case "ctrl+a":              return "\u{01}"
        case "ctrl+e":              return "\u{05}"
        case "ctrl+k":              return "\u{0B}"
        case "ctrl+u":              return "\u{15}"
        case "ctrl+w":              return "\u{17}"
        case "ctrl+r":              return "\u{12}"
        default:                    return nil
        }
    }

    @Test func returnKey() {
        #expect(Self.keyToText("return") == "\r")
        #expect(Self.keyToText("enter") == "\r")
        #expect(Self.keyToText("Return") == "\r")
    }

    @Test func controlKeys() {
        #expect(Self.keyToText("ctrl+c") == "\u{03}")
        #expect(Self.keyToText("ctrl+d") == "\u{04}")
        #expect(Self.keyToText("ctrl+z") == "\u{1A}")
    }

    @Test func specialKeys() {
        #expect(Self.keyToText("tab") == "\t")
        #expect(Self.keyToText("space") == " ")
        #expect(Self.keyToText("escape") == "\u{1B}")
        #expect(Self.keyToText("backspace") == "\u{7F}")
    }

    @Test func unknownKeyReturnsNil() {
        #expect(Self.keyToText("f13") == nil)
        #expect(Self.keyToText("unknown") == nil)
    }
}

#endif
