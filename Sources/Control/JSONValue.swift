// ABOUTME: A JSON value that keeps object key order and number text, written in
// ABOUTME: the 2-space format Claude Code uses, so editing a file changes only what we touch.

import Foundation

struct JSONMember: Equatable {
    var key: String
    var value: JSONValue
}

indirect enum JSONValue: Equatable {
    case object([JSONMember])
    case array([JSONValue])
    case string(String)
    /// The number's text as it appeared, so `1.0` is not rewritten as `1`.
    case number(String)
    case bool(Bool)
    case null

    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }

    /// Replaces the member named `key` in place, or appends it when absent.
    /// A nil value removes the member. Anything but an object is unchanged.
    func setting(_ key: String, to value: JSONValue?) -> JSONValue {
        guard case .object(var members) = self else { return self }
        if let index = members.firstIndex(where: { $0.key == key }) {
            if let value { members[index].value = value } else { members.remove(at: index) }
        } else if let value {
            members.append(JSONMember(key: key, value: value))
        }
        return .object(members)
    }

    static func parse(_ text: String) -> JSONValue? {
        var parser = JSONParser(bytes: Array(text.utf8))
        guard let value = parser.parseValue() else { return nil }
        parser.skipWhitespace()
        return parser.atEnd ? value : nil
    }

    /// The text `JSON.stringify(value, null, 2)` produces.
    func formatted() -> String {
        var output = ""
        write(to: &output, indent: "")
        return output
    }

    private func write(to output: inout String, indent: String) {
        let inner = indent + "  "
        switch self {
        case .object(let members) where members.isEmpty:
            output += "{}"
        case .object(let members):
            output += "{\n"
            for (index, member) in members.enumerated() {
                output += inner + Self.quoted(member.key) + ": "
                member.value.write(to: &output, indent: inner)
                output += index == members.count - 1 ? "\n" : ",\n"
            }
            output += indent + "}"
        case .array(let elements) where elements.isEmpty:
            output += "[]"
        case .array(let elements):
            output += "[\n"
            for (index, element) in elements.enumerated() {
                output += inner
                element.write(to: &output, indent: inner)
                output += index == elements.count - 1 ? "\n" : ",\n"
            }
            output += indent + "]"
        case .string(let text):
            output += Self.quoted(text)
        case .number(let text):
            output += text
        case .bool(let flag):
            output += flag ? "true" : "false"
        case .null:
            output += "null"
        }
    }

    private static func quoted(_ text: String) -> String {
        var output = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\u{08}": output += "\\b"
            case "\u{0C}": output += "\\f"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case _ where scalar.value < 0x20:
                output += String(format: "\\u%04x", scalar.value)
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        return output + "\""
    }
}

private struct JSONParser {
    let bytes: [UInt8]
    var index = 0

    var atEnd: Bool { index == bytes.count }

    private var current: UInt8? { index < bytes.count ? bytes[index] : nil }

    mutating func skipWhitespace() {
        while let byte = current, [0x20, 0x09, 0x0A, 0x0D].contains(byte) { index += 1 }
    }

    mutating func parseValue() -> JSONValue? {
        skipWhitespace()
        switch current {
        case UInt8(ascii: "{"): return parseObject()
        case UInt8(ascii: "["): return parseArray()
        case UInt8(ascii: "\""): return parseString().map(JSONValue.string)
        case UInt8(ascii: "t"): return consume("true") ? .bool(true) : nil
        case UInt8(ascii: "f"): return consume("false") ? .bool(false) : nil
        case UInt8(ascii: "n"): return consume("null") ? .null : nil
        default: return parseNumber()
        }
    }

    private mutating func consume(_ literal: String) -> Bool {
        let expected = Array(literal.utf8)
        guard bytes.count - index >= expected.count,
              Array(bytes[index..<index + expected.count]) == expected else { return false }
        index += expected.count
        return true
    }

    private mutating func parseObject() -> JSONValue? {
        index += 1
        var members: [JSONMember] = []
        skipWhitespace()
        if consume("}") { return .object(members) }
        while true {
            skipWhitespace()
            guard current == UInt8(ascii: "\""), let key = parseString() else { return nil }
            skipWhitespace()
            guard consume(":"), let value = parseValue() else { return nil }
            members.append(JSONMember(key: key, value: value))
            skipWhitespace()
            if consume("}") { return .object(members) }
            guard consume(",") else { return nil }
        }
    }

    private mutating func parseArray() -> JSONValue? {
        index += 1
        var elements: [JSONValue] = []
        skipWhitespace()
        if consume("]") { return .array(elements) }
        while true {
            guard let element = parseValue() else { return nil }
            elements.append(element)
            skipWhitespace()
            if consume("]") { return .array(elements) }
            guard consume(",") else { return nil }
        }
    }

    private mutating func parseNumber() -> JSONValue? {
        let start = index
        while let byte = current, "+-.eE0123456789".utf8.contains(byte) { index += 1 }
        guard let text = String(bytes: bytes[start..<index], encoding: .utf8) else { return nil }
        let grammar = #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#
        guard text.range(of: grammar, options: .regularExpression) != nil else { return nil }
        return .number(text)
    }

    private mutating func parseString() -> String? {
        index += 1
        var scalars = String.UnicodeScalarView()
        var raw: [UInt8] = []
        func flush() -> Bool {
            guard let text = String(bytes: raw, encoding: .utf8) else { return false }
            scalars.append(contentsOf: text.unicodeScalars)
            raw.removeAll()
            return true
        }
        while let byte = current {
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                return flush() ? String(scalars) : nil
            case UInt8(ascii: "\\"):
                guard flush(), let scalar = parseEscape() else { return nil }
                scalars.append(scalar)
            case 0x00..<0x20:
                return nil
            default:
                raw.append(byte)
            }
        }
        return nil
    }

    private static let simpleEscapes: [UInt8: Unicode.Scalar] = [
        UInt8(ascii: "\""): "\"", UInt8(ascii: "\\"): "\\", UInt8(ascii: "/"): "/",
        UInt8(ascii: "b"): "\u{08}", UInt8(ascii: "f"): "\u{0C}", UInt8(ascii: "n"): "\n",
        UInt8(ascii: "r"): "\r", UInt8(ascii: "t"): "\t"
    ]

    private mutating func parseEscape() -> Unicode.Scalar? {
        guard let byte = current else { return nil }
        index += 1
        return byte == UInt8(ascii: "u") ? parseUnicodeEscape() : Self.simpleEscapes[byte]
    }

    private mutating func parseUnicodeEscape() -> Unicode.Scalar? {
        guard let high = parseHex4() else { return nil }
        guard (0xD800...0xDBFF).contains(high) else { return Unicode.Scalar(high) }
        guard consume("\\u"), let low = parseHex4(), (0xDC00...0xDFFF).contains(low) else { return nil }
        return Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00))
    }

    private mutating func parseHex4() -> UInt32? {
        guard bytes.count - index >= 4 else { return nil }
        guard let text = String(bytes: bytes[index..<index + 4], encoding: .ascii),
              text.allSatisfy(\.isHexDigit),
              let value = UInt32(text, radix: 16) else { return nil }
        index += 4
        return value
    }
}
