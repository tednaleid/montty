// ABOUTME: What the read form of a setting prints, worked out from the info
// ABOUTME: reply a running montty sends back over the control socket.

import Foundation

enum SettingReadout {
    /// The text to print for a setting read at a scope, or nil when there is
    /// nothing to print. `info` is the info reply as a plain dictionary, with
    /// the snake-cased keys it has on the wire.
    static func text(_ read: SettingRead, info: [String: Any]) -> String? {
        switch read.setting {
        case .color:
            return color(at: read.scope, info: info)
        case .name:
            return info["tab_name"] as? String
        case .status:
            return info["status"] as? String
        case .resumeCommand:
            return info["resume_command"] as? String
        case .surfaceTintStrength, .tabTintStrength, .minimap, .minimapHeight:
            return scoped(read, info: info)
        }
    }

    /// A scope with no color of its own reports what the surface renders
    /// instead, since a color can also come from the git signature.
    private static func color(at scope: SettingScope, info: [String: Any]) -> String {
        let scopes = info["scopes"] as? [String: Any]
        if let own = (scopes?[scope.rawValue] as? [String: Any])?["stops"] as? [String] {
            return own.joined(separator: ",")
        }
        let effective = (info["effective"] as? [String: Any])?["stops"] as? [String]
        return "not set (effective \(effective?.joined(separator: ",") ?? "none"))"
    }

    /// The value at the scope asked for, or failing that at the next wider
    /// scope that has one.
    private static func scoped(_ read: SettingRead, info: [String: Any]) -> String? {
        let settings = info["settings"] as? [String: Any]
        guard let entry = settings?[read.setting.infoKey] as? [String: Any],
              let start = SettingScope.allCases.firstIndex(of: read.scope) else { return nil }
        return SettingScope.allCases[start...]
            .lazy.compactMap { entry[$0.rawValue] }
            .first.map(render)
    }

    private static func render(_ value: Any) -> String {
        if let text = value as? String { return text }
        guard let number = value as? Double else { return "\(value)" }
        return number == number.rounded() ? "\(Int(number))" : "\(number)"
    }
}
