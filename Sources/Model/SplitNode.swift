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
