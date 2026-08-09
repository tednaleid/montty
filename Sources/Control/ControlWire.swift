// ABOUTME: JSON envelope for the montty control socket: one versioned request
// ABOUTME: per connection, one response, then close.

import Foundation

enum ControlWire {
    /// Bumped only when the envelope shape changes incompatibly.
    static let version = 1
}

/// One request carries exactly one command, matching one ControlCommand.
struct ControlRequest: Equatable {
    let surface: String
    let command: ControlCommand

    enum DecodeFailure: Error, Equatable {
        case malformed
        case unsupportedVersion
        /// No `cmd` field: a hook event from the shell wrapper, which the
        /// legacy ClaudeHookMessage path still owns.
        case legacyHook
    }

    static func decode(_ data: Data) throws -> ControlRequest {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            throw DecodeFailure.malformed
        }
        guard let cmd = root["cmd"] as? String else {
            throw DecodeFailure.legacyHook
        }
        guard ((root["v"] as? Int) ?? 0) <= ControlWire.version else {
            throw DecodeFailure.unsupportedVersion
        }
        guard let surface = root["surface"] as? String, !surface.isEmpty else {
            throw DecodeFailure.malformed
        }

        switch cmd {
        case "info":
            return ControlRequest(surface: surface, command: .info)
        case "set":
            return ControlRequest(
                surface: surface,
                command: try setCommand(root)
            )
        default:
            throw DecodeFailure.malformed
        }
    }

    private static func setCommand(_ root: [String: Any]) throws -> ControlCommand {
        guard let prop = root["prop"] as? String else { throw DecodeFailure.malformed }
        // NSNull is how JSONSerialization reports an explicit null, which is
        // the clear form. A missing key is malformed, not a clear.
        guard root.keys.contains("value") else { throw DecodeFailure.malformed }
        let value = root["value"]
        let isNull = value == nil || value is NSNull

        switch prop {
        case "color":
            return try colorCommand(root: root, value: value, isNull: isNull)
        case "name":
            return try nameCommand(value: value, isNull: isNull)
        case "status":
            return try statusCommand(value: value, isNull: isNull)
        default:
            throw DecodeFailure.malformed
        }
    }

    private static func colorCommand(
        root: [String: Any], value: Any?, isNull: Bool
    ) throws -> ControlCommand {
        let scope = ControlScope(rawValue: root["scope"] as? String ?? "")
        guard let scope else { throw DecodeFailure.malformed }
        if isNull { return .clearColor(scope: scope) }
        guard let texts = value as? [String] else { throw DecodeFailure.malformed }
        let stops = texts.compactMap(TintStop.parse)
        guard stops.count == texts.count, !stops.isEmpty,
              stops.count <= PaneTint.maxStops else {
            throw DecodeFailure.malformed
        }
        return .setColor(scope: scope, tint: PaneTint(stops: stops))
    }

    private static func nameCommand(value: Any?, isNull: Bool) throws -> ControlCommand {
        if isNull { return .clearName }
        guard let name = value as? String else { throw DecodeFailure.malformed }
        return .setName(name)
    }

    private static func statusCommand(value: Any?, isNull: Bool) throws -> ControlCommand {
        if isNull { return .setStatus(nil) }
        guard let text = value as? String else { throw DecodeFailure.malformed }
        switch text {
        case "working": return .setStatus(.working)
        case "waiting": return .setStatus(.waiting)
        case "idle": return .setStatus(.idle)
        default: throw DecodeFailure.malformed
        }
    }

    func encoded() throws -> Data {
        var root: [String: Any] = ["v": ControlWire.version, "surface": surface]
        switch command {
        case .info:
            root["cmd"] = "info"
        case .setColor(let scope, let tint):
            root["cmd"] = "set"
            root["prop"] = "color"
            root["scope"] = scope.rawValue
            root["value"] = tint.stops.map(\.text)
        case .clearColor(let scope):
            root["cmd"] = "set"
            root["prop"] = "color"
            root["scope"] = scope.rawValue
            root["value"] = NSNull()
        case .setName(let name):
            root["cmd"] = "set"
            root["prop"] = "name"
            root["value"] = name
        case .clearName:
            root["cmd"] = "set"
            root["prop"] = "name"
            root["value"] = NSNull()
        case .setStatus(let status):
            root["cmd"] = "set"
            root["prop"] = "status"
            root["value"] = status.map { String(describing: $0) } ?? NSNull()
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
}

enum ControlResponse {
    case ok
    case failure(String)
    case info(ControlInfo)

    func encoded() throws -> Data {
        switch self {
        case .ok:
            return try JSONSerialization.data(
                withJSONObject: ["ok": true], options: [.sortedKeys]
            )
        case .failure(let message):
            return try JSONSerialization.data(
                withJSONObject: ["ok": false, "error": message], options: [.sortedKeys]
            )
        case .info(let info):
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(info)
            guard var root = try JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
                return try ControlResponse.failure("info encoding failed").encoded()
            }
            root["ok"] = true
            return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        }
    }
}
