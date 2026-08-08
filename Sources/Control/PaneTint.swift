// ABOUTME: Ordered gradient stops for a pane, leading edge to trailing edge.
// ABOUTME: The shared currency for surface, tab, and repo color overrides.

import Foundation

/// One stop renders solid, two is a repo's own signature, and three is a
/// worktree carrying its parent repo's pair ahead of its own color.
struct PaneTint: Equatable, Hashable {
    static let maxStops = 3

    let stops: [TintStop]

    init(stops: [TintStop]) {
        let clamped = Array(stops.prefix(Self.maxStops))
        self.stops = clamped.isEmpty ? [.named(.gray)] : clamped
    }

    /// The stop to use wherever only one can be shown. Always the trailing
    /// stop: a repo's own color, or a worktree's own color.
    var primary: TintStop { stops.last ?? .named(.gray) }

    /// The leading stop, used for the tab row's left edge bar.
    var leading: TintStop { stops.first ?? .named(.gray) }

    var isGradient: Bool { stops.count > 1 }
}

extension PaneTint: Codable {
    /// Accepts a bare string from a v2 session or an array of stops. One
    /// decoder covers every migration point, so no field needs a version
    /// branch of its own.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(TintStop.self) {
            self.init(stops: [single])
            return
        }
        self.init(stops: try container.decode([TintStop].self))
    }

    /// A single stop encodes back as a bare string, so a session without
    /// gradients stays readable by a build that predates this format.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if stops.count == 1 {
            try container.encode(stops[0])
        } else {
            try container.encode(stops)
        }
    }
}
