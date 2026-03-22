import Foundation

indirect enum SplitNode: Identifiable, Equatable, Codable {
    case leaf(SurfaceLeaf)
    case split(SplitBranch)

    var id: UUID {
        switch self {
        case .leaf(let leaf): leaf.id
        case .split(let branch): branch.id
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, leaf, branch
    }

    private enum NodeType: String, Codable {
        case leaf, split
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .leaf(let leaf):
            try container.encode(NodeType.leaf, forKey: .type)
            try container.encode(leaf, forKey: .leaf)
        case .split(let branch):
            try container.encode(NodeType.split, forKey: .type)
            try container.encode(branch, forKey: .branch)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nodeType = try container.decode(NodeType.self, forKey: .type)
        switch nodeType {
        case .leaf:
            self = .leaf(try container.decode(SurfaceLeaf.self, forKey: .leaf))
        case .split:
            self = .split(try container.decode(SplitBranch.self, forKey: .branch))
        }
    }
}

struct SurfaceLeaf: Identifiable, Equatable, Codable {
    let id: UUID
    var surfaceID: UUID

    init(id: UUID = UUID(), surfaceID: UUID = UUID()) {
        self.id = id
        self.surfaceID = surfaceID
    }
}

struct SplitBranch: Identifiable, Equatable, Codable {
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
