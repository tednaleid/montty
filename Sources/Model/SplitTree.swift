import Foundation

enum SplitTree {
    /// Split the leaf with the given ID, inserting a new leaf beside it.
    static func split(
        node: SplitNode,
        leafID: UUID,
        orientation: SplitOrientation,
        newLeafID: UUID = UUID(),
        newSurfaceID: UUID = UUID()
    ) -> SplitNode {
        switch node {
        case .leaf(let leaf):
            guard leaf.id == leafID else { return node }
            let newLeaf = SurfaceLeaf(id: newLeafID, surfaceID: newSurfaceID)
            return .split(SplitBranch(
                orientation: orientation,
                first: .leaf(leaf),
                second: .leaf(newLeaf)
            ))

        case .split(let branch):
            let newFirst = split(
                node: branch.first, leafID: leafID,
                orientation: orientation,
                newLeafID: newLeafID, newSurfaceID: newSurfaceID
            )
            let newSecond = split(
                node: branch.second, leafID: leafID,
                orientation: orientation,
                newLeafID: newLeafID, newSurfaceID: newSurfaceID
            )
            return .split(SplitBranch(
                id: branch.id,
                orientation: branch.orientation,
                ratio: branch.ratio,
                first: newFirst,
                second: newSecond
            ))
        }
    }

    /// Remove a leaf by ID, collapsing its parent branch.
    /// Returns nil if the tree becomes empty (last leaf removed).
    static func close(node: SplitNode, leafID: UUID) -> SplitNode? {
        switch node {
        case .leaf(let leaf):
            return leaf.id == leafID ? nil : node

        case .split(let branch):
            let closedFirst = close(node: branch.first, leafID: leafID)
            let closedSecond = close(node: branch.second, leafID: leafID)

            switch (closedFirst, closedSecond) {
            case (nil, nil):
                return nil
            case (nil, let remaining):
                return remaining
            case (let remaining, nil):
                return remaining
            case (let first?, let second?):
                return .split(SplitBranch(
                    id: branch.id,
                    orientation: branch.orientation,
                    ratio: branch.ratio,
                    first: first,
                    second: second
                ))
            }
        }
    }

    /// Find a leaf by its surface ID.
    static func findLeaf(node: SplitNode, surfaceID: UUID) -> SurfaceLeaf? {
        switch node {
        case .leaf(let leaf):
            return leaf.surfaceID == surfaceID ? leaf : nil
        case .split(let branch):
            return findLeaf(node: branch.first, surfaceID: surfaceID)
                ?? findLeaf(node: branch.second, surfaceID: surfaceID)
        }
    }

    /// Collect all leaves in order (left-to-right, top-to-bottom).
    static func allLeaves(node: SplitNode) -> [SurfaceLeaf] {
        switch node {
        case .leaf(let leaf):
            return [leaf]
        case .split(let branch):
            return allLeaves(node: branch.first) + allLeaves(node: branch.second)
        }
    }

    /// Find the next leaf after the given leaf ID, wrapping around.
    static func nextLeaf(node: SplitNode, after leafID: UUID) -> SurfaceLeaf? {
        let leaves = allLeaves(node: node)
        guard let index = leaves.firstIndex(where: { $0.id == leafID }) else { return nil }
        let nextIndex = (index + 1) % leaves.count
        return leaves[nextIndex]
    }

    /// Find the previous leaf before the given leaf ID, wrapping around.
    static func previousLeaf(node: SplitNode, before leafID: UUID) -> SurfaceLeaf? {
        let leaves = allLeaves(node: node)
        guard let index = leaves.firstIndex(where: { $0.id == leafID }) else { return nil }
        let prevIndex = (index - 1 + leaves.count) % leaves.count
        return leaves[prevIndex]
    }
}
