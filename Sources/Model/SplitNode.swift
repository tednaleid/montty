import Foundation

indirect enum SplitNode: Identifiable, Equatable {
    case leaf(SurfaceLeaf)
    case split(SplitBranch)

    var id: UUID {
        switch self {
        case .leaf(let leaf): leaf.id
        case .split(let branch): branch.id
        }
    }
}

struct SurfaceLeaf: Identifiable, Equatable {
    let id: UUID
    var surfaceID: UUID

    init(id: UUID = UUID(), surfaceID: UUID = UUID()) {
        self.id = id
        self.surfaceID = surfaceID
    }
}

struct SplitBranch: Identifiable, Equatable {
    let id: UUID
    var orientation: SplitOrientation
    var ratio: CGFloat
    var first: SplitNode
    var second: SplitNode

    init(
        id: UUID = UUID(),
        orientation: SplitOrientation,
        ratio: CGFloat = 0.5,
        first: SplitNode,
        second: SplitNode
    ) {
        self.id = id
        self.orientation = orientation
        self.ratio = ratio
        self.first = first
        self.second = second
    }
}

enum SplitOrientation: String, Codable {
    case horizontal // left | right
    case vertical   // top / bottom
}

/// Directional intent for split creation and navigation.
enum SplitDirection {
    case left, right, up, down

    var orientation: SplitOrientation {
        switch self {
        case .left, .right: return .horizontal
        case .up, .down: return .vertical
        }
    }

    /// Whether the new pane should be placed first (before the original).
    var newPaneFirst: Bool {
        switch self {
        case .left, .up: return true
        case .right, .down: return false
        }
    }
}
