// ABOUTME: The rule deciding whether a tab row shows its minimap, its CLI text
// ABOUTME: form, and the bounds on how tall a shown minimap is.

import Foundation

/// A circumstance under which a conditionally visible minimap shows.
enum MinimapCondition: String, CaseIterable {
    /// The tab has more than one surface.
    case split
    /// Any surface in the tab has an activity status, idle included.
    case status

    var menuTitle: String {
        switch self {
        case .split: return "When Split"
        case .status: return "When Status"
        }
    }
}

enum MinimapVisibility: Equatable {
    case always
    case never
    /// Shown while at least one of these holds. Never empty: `parse` rejects an
    /// empty list and `toggling` turns one into `never`.
    case when(Set<MinimapCondition>)

    /// What a montty with no saved session starts with, and what resetting
    /// the app scope returns to: a minimap only for a tab that is split.
    static let `default` = MinimapVisibility.when([.split])

    /// Reads the CLI and session form: `always`, `never`, or a comma-separated
    /// list of conditions in any order.
    static func parse(_ text: String) -> MinimapVisibility? {
        switch text {
        case "always": return .always
        case "never": return .never
        default:
            let parts = text.components(separatedBy: ",")
            let conditions = Set(parts.compactMap(MinimapCondition.init(rawValue:)))
            // Fewer conditions than parts means an unknown or a repeated one.
            guard conditions.count == parts.count else { return nil }
            return .when(conditions)
        }
    }

    /// The form `parse` reads back, with conditions in declaration order.
    var text: String {
        switch self {
        case .always: return "always"
        case .never: return "never"
        case .when(let conditions):
            return MinimapCondition.allCases
                .filter(conditions.contains)
                .map(\.rawValue)
                .joined(separator: ",")
        }
    }

    func shows(surfaceCount: Int, hasStatus: Bool) -> Bool {
        switch self {
        case .always: return true
        case .never: return false
        case .when(let conditions):
            return (conditions.contains(.split) && surfaceCount > 1)
                || (conditions.contains(.status) && hasStatus)
        }
    }

    func includes(_ condition: MinimapCondition) -> Bool {
        guard case .when(let conditions) = self else { return false }
        return conditions.contains(condition)
    }

    /// What checking or unchecking one condition in a menu produces. From
    /// `always` or `never` the condition stands alone, and unchecking the last
    /// one leaves `never`.
    func toggling(_ condition: MinimapCondition) -> MinimapVisibility {
        guard case .when(var conditions) = self else { return .when([condition]) }
        if conditions.remove(condition) == nil {
            conditions.insert(condition)
        }
        return conditions.isEmpty ? .never : .when(conditions)
    }
}

extension MinimapVisibility: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let parsed = MinimapVisibility.parse(text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "not a minimap visibility: \(text)"
            )
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}

/// Height in points of a shown minimap, app-wide.
enum MinimapHeight {
    static let `default`: Double = 90
    /// The floor keeps a single-surface minimap tall enough for the activity
    /// indicator, which does not scale with the minimap.
    static let range: ClosedRange<Double> = 40...200
}
