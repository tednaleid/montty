// ABOUTME: JSON envelope for the montty control socket: one versioned request
// ABOUTME: per connection, one response, then close.

import Foundation

enum ControlWire {
    /// Bumped only when the envelope shape changes incompatibly.
    static let version = 1

    /// Longest tab name a client may set. A tab name is a sidebar label, and a
    /// row shows a few dozen characters, so 256 is room for a full pull request
    /// title with decoration. Past that the value is not a label, and every one
    /// of its characters is re-encoded into the session file on each autosave.
    static let maxNameCharacters = 256
}

/// The one request that reaches no tab and changes nothing: it asks only
/// whether a montty is on the other end of a socket. A startup guard uses it to
/// tell a running montty apart from a socket file left by a crash or from
/// another program squatting on the path.
enum ControlPing {
    static let command = "ping"

    /// What a client sends. No surface, because being alive is a property of
    /// the process rather than of a pane.
    static let request = Data(#"{"cmd":"\#(command)","v":\#(ControlWire.version)}"#.utf8)

    /// True when `data` asks for liveness. The server checks this before
    /// decoding a request, which requires a surface and so would call a ping
    /// malformed.
    static func isRequest(_ data: Data) -> Bool {
        root(of: data)?["cmd"] as? String == command
    }

    /// True when `data` is the answer a montty that knows the ping gives. A
    /// server that predates it answers `ok: false`, so the caller reads no
    /// montty rather than failing.
    static func isReply(_ data: Data) -> Bool {
        root(of: data)?["ok"] as? Bool == true
    }

    private static func root(of data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// One request carries exactly one command, matching one ControlCommand.
struct ControlRequest: Equatable {
    let surface: String
    let command: ControlCommand

    enum DecodeFailure: Error, Equatable {
        case malformed
        case unsupportedVersion
        /// A name past `ControlWire.maxNameCharacters`. Rejected rather than
        /// truncated, so a caller is never told a name it never chose is set.
        case nameTooLong
        /// A resume command that is empty, past `ResumeCommand.maxCharacters`,
        /// or holds a control character that would act on its own when typed.
        case invalidResumeCommand
        /// A new-tab request whose directory is not absolute or whose command
        /// cannot be run.
        case invalidNewTab
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
        case "new-tab":
            return ControlRequest(surface: surface, command: .newTab(try newTabCommand(root)))
        case "launch":
            return ControlRequest(surface: surface, command: .takeLaunch)
        case "set":
            return ControlRequest(
                surface: surface,
                command: try setCommand(root)
            )
        default:
            throw DecodeFailure.malformed
        }
    }

    private static func newTabCommand(_ root: [String: Any]) throws -> NewTab {
        var spec = NewTab()
        if let directory = root["dir"] as? String {
            guard NewTab.isValidDirectory(directory) else { throw DecodeFailure.invalidNewTab }
            spec.directory = directory
        }
        if let name = root["name"] as? String {
            guard name.count <= ControlWire.maxNameCharacters else { throw DecodeFailure.nameTooLong }
            spec.name = name
        }
        if let command = root["command"] as? [String] {
            guard NewTab.isValidCommand(command) else { throw DecodeFailure.invalidNewTab }
            spec.command = command
        }
        spec.focus = root["focus"] as? Bool ?? false
        return spec
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
        case "name", "surfaceName":
            return try nameCommand(prop: prop, value: value, isNull: isNull)
        case "status":
            return try statusCommand(value: value, isNull: isNull)
        case "surfaceTintStrength", "tabTintStrength":
            return try strengthCommand(root: root, value: value, isNull: isNull)
        case "resumeCommand":
            return try resumeCommand(value: value, isNull: isNull)
        case "minimapVisibility", "tabMinimapVisibility", "minimapHeight":
            return try minimapCommand(root: root, value: value, isNull: isNull)
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

    private static func nameCommand(
        prop: String, value: Any?, isNull: Bool
    ) throws -> ControlCommand {
        let ofSurface = prop == "surfaceName"
        if isNull { return ofSurface ? .setSurfaceName(nil) : .clearName }
        guard let name = value as? String else { throw DecodeFailure.malformed }
        guard name.count <= ControlWire.maxNameCharacters else {
            throw DecodeFailure.nameTooLong
        }
        return ofSurface ? .setSurfaceName(name) : .setName(name)
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

    private static func resumeCommand(value: Any?, isNull: Bool) throws -> ControlCommand {
        if isNull { return .setResumeCommand(nil) }
        guard let command = value as? String else { throw DecodeFailure.malformed }
        guard ResumeCommand.isValid(command) else { throw DecodeFailure.invalidResumeCommand }
        return .setResumeCommand(command)
    }

    private static func strengthCommand(
        root: [String: Any], value: Any?, isNull: Bool
    ) throws -> ControlCommand {
        guard let setting = StrengthSetting(rawValue: root["prop"] as? String ?? ""),
              let scope = SettingScope(rawValue: root["scope"] as? String ?? "") else {
            throw DecodeFailure.malformed
        }
        if isNull { return .setStrength(setting, scope: scope, value: nil) }
        guard let strength = value as? Double, setting.range.contains(strength) else {
            throw DecodeFailure.malformed
        }
        return .setStrength(setting, scope: scope, value: strength)
    }

    private static func minimapCommand(
        root: [String: Any], value: Any?, isNull: Bool
    ) throws -> ControlCommand {
        let prop = root["prop"] as? String
        if prop == "minimapHeight" {
            let scope = SettingScope(rawValue: root["scope"] as? String ?? "")
            guard let scope, scope == .tab || scope == .app else { throw DecodeFailure.malformed }
            if isNull { return .setMinimapHeight(scope: scope, value: nil) }
            guard let height = value as? Double, MinimapHeight.range.contains(height) else {
                throw DecodeFailure.malformed
            }
            return .setMinimapHeight(scope: scope, value: height)
        }
        if isNull, prop == "tabMinimapVisibility" { return .setTabMinimapVisibility(nil) }
        guard let text = value as? String,
              let visibility = MinimapVisibility.parse(text) else {
            throw DecodeFailure.malformed
        }
        return prop == "minimapVisibility"
            ? .setMinimapVisibility(visibility) : .setTabMinimapVisibility(visibility)
    }

    /// The fields a scoped setting, minimap, or surface name command travels
    /// under.
    private var settingFields: [String: Any] {
        switch command {
        case .setStrength(let setting, let scope, let value):
            return ["prop": setting.rawValue, "scope": scope.rawValue, "value": value ?? NSNull()]
        case .setSurfaceName(let name):
            return ["prop": "surfaceName", "value": name ?? NSNull()]
        case .setMinimapVisibility(let visibility):
            return ["prop": "minimapVisibility", "value": visibility.text]
        case .setTabMinimapVisibility(let visibility):
            return ["prop": "tabMinimapVisibility", "value": visibility?.text ?? NSNull()]
        case .setMinimapHeight(let scope, let height):
            return ["prop": "minimapHeight", "scope": scope.rawValue, "value": height ?? NSNull()]
        default:
            return [:]
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
            root["value"] = status.map(\.wireName) ?? NSNull()
        case .setResumeCommand(let command):
            root["cmd"] = "set"
            root["prop"] = "resumeCommand"
            root["value"] = command ?? NSNull()
        case .setMinimapVisibility, .setTabMinimapVisibility, .setMinimapHeight,
             .setStrength, .setSurfaceName:
            root["cmd"] = "set"
            root.merge(settingFields) { _, field in field }
        case .newTab(let spec):
            root["cmd"] = "new-tab"
            root["dir"] = spec.directory
            root["name"] = spec.name
            root["command"] = spec.command
            root["focus"] = spec.focus
        case .takeLaunch:
            root["cmd"] = "launch"
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
}

enum ControlResponse {
    // swiftlint:disable:next identifier_name
    case ok
    case failure(String)
    case info(ControlInfo)
    case launch([String])

    func encoded() throws -> Data {
        switch self {
        case .launch(let command):
            return try JSONSerialization.data(
                withJSONObject: ["ok": true, "command": command], options: [.sortedKeys]
            )
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
