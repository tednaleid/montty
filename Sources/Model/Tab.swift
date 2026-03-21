import Foundation

@Observable
final class Tab: Identifiable {
    let id: UUID
    var name: String
    var autoName: String
    var color: TabColor
    var position: Int
    var workingDirectory: String?
    var splitRoot: SplitNode
    var focusedLeafID: UUID?

    var displayName: String {
        name.isEmpty ? autoName : name
    }

    /// The surfaceID of the focused leaf, or the first leaf if none focused.
    var focusedSurfaceID: UUID? {
        if let focusedLeafID = focusedLeafID,
           let leaves = Optional(SplitTree.allLeaves(node: splitRoot)),
           let leaf = leaves.first(where: { $0.id == focusedLeafID }) {
            return leaf.surfaceID
        }
        return SplitTree.allLeaves(node: splitRoot).first?.surfaceID
    }

    /// All surface IDs in this tab's split tree.
    var allSurfaceIDs: [UUID] {
        SplitTree.allLeaves(node: splitRoot).map(\.surfaceID)
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        autoName: String = "",
        color: TabColor = .auto,
        position: Int = 0,
        workingDirectory: String? = nil,
        surfaceID: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.autoName = autoName
        self.color = color
        self.position = position
        self.workingDirectory = workingDirectory
        let leaf = SurfaceLeaf(surfaceID: surfaceID)
        self.splitRoot = .leaf(leaf)
        self.focusedLeafID = leaf.id
    }
}
