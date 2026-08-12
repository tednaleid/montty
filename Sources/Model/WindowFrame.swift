// ABOUTME: A window's saved position and size, and the clamp that keeps a
// ABOUTME: restored window on a display that is actually attached.

import CoreGraphics
import Foundation

struct WindowFrame: Codable, Equatable {
    // swiftlint:disable:next identifier_name
    var x: Double
    // swiftlint:disable:next identifier_name
    var y: Double
    var width: Double
    var height: Double

    /// A window that was never laid out has nothing worth restoring.
    var isEmpty: Bool { width <= 0 || height <= 0 }

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    // swiftlint:disable:next identifier_name
    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x, y: rect.origin.y,
            width: rect.width, height: rect.height
        )
    }

    /// Moves the frame onto the visible screen it overlaps most, or onto the
    /// first screen when it overlaps none. A display that was attached when the
    /// session was saved may be gone by the time it is restored, and a window
    /// placed on it would open where nobody can reach it.
    func clamped(toVisible frames: [CGRect]) -> WindowFrame {
        guard let target = frames.max(by: {
            $0.intersection(rect).area < $1.intersection(rect).area
        }) ?? frames.first else { return self }

        if target.intersection(rect).area > 0, target.contains(rect) { return self }

        let width = min(self.width, target.width)
        let height = min(self.height, target.height)
        // swiftlint:disable:next identifier_name
        let x = min(max(self.x, target.minX), target.maxX - width)
        // swiftlint:disable:next identifier_name
        let y = min(max(self.y, target.minY), target.maxY - height)
        return WindowFrame(x: x, y: y, width: width, height: height)
    }
}

private extension CGRect {
    var area: Double { isNull ? 0 : width * height }
}
