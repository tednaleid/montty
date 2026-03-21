import Foundation

enum SplitTree {
    /// Split the leaf with the given ID, inserting a new leaf beside it.
    /// When `newPaneFirst` is true, the new leaf becomes the first child
    /// (used for left/up splits so the new pane appears before the original).
    static func split(
        node: SplitNode,
        leafID: UUID,
        orientation: SplitOrientation,
        newLeafID: UUID = UUID(),
        newSurfaceID: UUID = UUID(),
        newPaneFirst: Bool = false
    ) -> SplitNode {
        switch node {
        case .leaf(let leaf):
            guard leaf.id == leafID else { return node }
            let newLeaf = SurfaceLeaf(id: newLeafID, surfaceID: newSurfaceID)
            let first: SplitNode = newPaneFirst ? .leaf(newLeaf) : .leaf(leaf)
            let second: SplitNode = newPaneFirst ? .leaf(leaf) : .leaf(newLeaf)
            return .split(SplitBranch(
                orientation: orientation,
                first: first,
                second: second
            ))

        case .split(let branch):
            let newFirst = split(
                node: branch.first, leafID: leafID,
                orientation: orientation,
                newLeafID: newLeafID, newSurfaceID: newSurfaceID,
                newPaneFirst: newPaneFirst
            )
            let newSecond = split(
                node: branch.second, leafID: leafID,
                orientation: orientation,
                newLeafID: newLeafID, newSurfaceID: newSurfaceID,
                newPaneFirst: newPaneFirst
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

    // MARK: - Spatial navigation

    /// Find the neighboring leaf in a spatial direction by walking the split tree.
    ///
    /// For "go left": walk up to find the nearest horizontal split where the
    /// current leaf is in the second (right) child, then descend into the first
    /// (left) child taking the rightmost path to find the closest neighbor.
    static func findNeighbor(
        node: SplitNode, leafID: UUID, direction: SplitDirection
    ) -> SurfaceLeaf? {
        guard let path = pathToLeaf(node: node, leafID: leafID) else { return nil }

        // For left/up we must be in the second child to have a neighbor;
        // for right/down we must be in the first child.
        let fromPosition: ChildPosition
        let descendPreference: ChildPosition
        switch direction {
        case .left, .up:
            fromPosition = .second
            descendPreference = .second
        case .right, .down:
            fromPosition = .first
            descendPreference = .first
        }

        // Walk up the path looking for a matching split
        for i in stride(from: path.count - 1, through: 0, by: -1) {
            let step = path[i]
            if step.branch.orientation == direction.orientation
                && step.position == fromPosition
            {
                let sibling = fromPosition == .second
                    ? step.branch.first : step.branch.second
                return edgeLeaf(node: sibling, preference: descendPreference)
            }
        }

        return nil
    }

    /// Split using a direction (determines both orientation and child order).
    static func split(
        node: SplitNode,
        leafID: UUID,
        direction: SplitDirection,
        newLeafID: UUID = UUID(),
        newSurfaceID: UUID = UUID()
    ) -> SplitNode {
        split(
            node: node,
            leafID: leafID,
            orientation: direction.orientation,
            newLeafID: newLeafID,
            newSurfaceID: newSurfaceID,
            newPaneFirst: direction.newPaneFirst
        )
    }

    // MARK: - Private helpers

    private enum ChildPosition {
        case first, second
    }

    private struct PathStep {
        let branch: SplitBranch
        let position: ChildPosition
    }

    /// Build the path from root to the leaf with the given ID.
    private static func pathToLeaf(
        node: SplitNode, leafID: UUID
    ) -> [PathStep]? {
        switch node {
        case .leaf(let leaf):
            return leaf.id == leafID ? [] : nil
        case .split(let branch):
            if let path = pathToLeaf(node: branch.first, leafID: leafID) {
                return [PathStep(branch: branch, position: .first)] + path
            }
            if let path = pathToLeaf(node: branch.second, leafID: leafID) {
                return [PathStep(branch: branch, position: .second)] + path
            }
            return nil
        }
    }

    /// Find the leaf at the edge of a subtree. When preference is `.second`,
    /// descend toward the second child at each branch (rightmost/bottommost).
    private static func edgeLeaf(
        node: SplitNode, preference: ChildPosition
    ) -> SurfaceLeaf {
        switch node {
        case .leaf(let leaf):
            return leaf
        case .split(let branch):
            let child = preference == .second ? branch.second : branch.first
            return edgeLeaf(node: child, preference: preference)
        }
    }
}
