// ABOUTME: Converts between the runtime PaneTint overrides AppDelegate carries
// ABOUTME: and the single-named-color TabColor overrides SessionSnapshot stores.

import Foundation

extension AppDelegate {
    /// The session schema stores a single named color per override. A
    /// gradient or CLI-set hex override collapses to its trailing stop's
    /// named color for persistence, or drops if that stop isn't named.
    func legacyColor(from tint: PaneTint?) -> TabColor? {
        guard let tint, case .named(let color) = tint.primary else { return nil }
        return color
    }

    func legacyColorOverrides(from overrides: [String: PaneTint]) -> [String: TabColor] {
        overrides.compactMapValues { tint in
            guard case .named(let color) = tint.primary else { return nil }
            return color
        }
    }
}
