import Foundation
import Testing

struct SplitTreeTests {
    @Test func splitLeafCreatesHorizontalBranch() {
        let leaf = SurfaceLeaf(id: UUID(), surfaceID: UUID())
        let root = SplitNode.leaf(leaf)
        let newLeafID = UUID()
        let newSurfaceID = UUID()

        let result = SplitTree.split(
            node: root, leafID: leaf.id,
            orientation: .horizontal,
            newLeafID: newLeafID, newSurfaceID: newSurfaceID
        )

        guard case .split(let branch) = result else {
            Issue.record("Expected split branch")
            return
        }
        #expect(branch.orientation == .horizontal)
        #expect(branch.ratio == 0.5)

        guard case .leaf(let first) = branch.first else {
            Issue.record("Expected leaf")
            return
        }
        #expect(first.id == leaf.id)

        guard case .leaf(let second) = branch.second else {
            Issue.record("Expected leaf")
            return
        }
        #expect(second.id == newLeafID)
        #expect(second.surfaceID == newSurfaceID)
    }

    @Test func splitLeafCreatesVerticalBranch() {
        let leaf = SurfaceLeaf()
        let root = SplitNode.leaf(leaf)
        let newLeafID = UUID()

        let result = SplitTree.split(
            node: root, leafID: leaf.id,
            orientation: .vertical, newLeafID: newLeafID
        )

        guard case .split(let branch) = result else {
            Issue.record("Expected split branch")
            return
        }
        #expect(branch.orientation == .vertical)
    }

    @Test func closeLeafCollapsesParent() {
        let leaf1 = SurfaceLeaf()
        let leaf2 = SurfaceLeaf()
        let root = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(leaf1), second: .leaf(leaf2)
        ))

        let result = SplitTree.close(node: root, leafID: leaf2.id)

        guard case .leaf(let remaining) = result else {
            Issue.record("Expected single leaf after close")
            return
        }
        #expect(remaining.id == leaf1.id)
    }

    @Test func closeLastLeafReturnsNil() {
        let leaf = SurfaceLeaf()
        let root = SplitNode.leaf(leaf)

        let result = SplitTree.close(node: root, leafID: leaf.id)
        #expect(result == nil)
    }

    @Test func allLeavesReturnsInOrder() {
        let leaf1 = SurfaceLeaf()
        let leaf2 = SurfaceLeaf()
        let leaf3 = SurfaceLeaf()

        // Tree: (leaf1 | (leaf2 / leaf3))
        let inner = SplitBranch(
            orientation: .vertical,
            first: .leaf(leaf2), second: .leaf(leaf3)
        )
        let root = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(leaf1), second: .split(inner)
        ))

        let leaves = SplitTree.allLeaves(node: root)
        #expect(leaves.map(\.id) == [leaf1.id, leaf2.id, leaf3.id])
    }

    @Test func nextLeafWrapsAround() {
        let leaf1 = SurfaceLeaf()
        let leaf2 = SurfaceLeaf()
        let root = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(leaf1), second: .leaf(leaf2)
        ))

        #expect(SplitTree.nextLeaf(node: root, after: leaf1.id)?.id == leaf2.id)
        #expect(SplitTree.nextLeaf(node: root, after: leaf2.id)?.id == leaf1.id)
    }

    @Test func previousLeafWrapsAround() {
        let leaf1 = SurfaceLeaf()
        let leaf2 = SurfaceLeaf()
        let root = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(leaf1), second: .leaf(leaf2)
        ))

        #expect(SplitTree.previousLeaf(node: root, before: leaf1.id)?.id == leaf2.id)
        #expect(SplitTree.previousLeaf(node: root, before: leaf2.id)?.id == leaf1.id)
    }

    @Test func splitDeepNestedLeaf() {
        let leaf1 = SurfaceLeaf()
        let leaf2 = SurfaceLeaf()
        let leaf3 = SurfaceLeaf()

        let inner = SplitBranch(
            orientation: .vertical,
            first: .leaf(leaf2), second: .leaf(leaf3)
        )
        let root = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(leaf1), second: .split(inner)
        ))

        let newLeafID = UUID()
        let result = SplitTree.split(
            node: root, leafID: leaf3.id,
            orientation: .horizontal, newLeafID: newLeafID
        )

        let allLeaves = SplitTree.allLeaves(node: result)
        #expect(allLeaves.count == 4)
        #expect(allLeaves.map(\.id).contains(newLeafID))
    }

    @Test func findLeafBySurfaceID() {
        let surfaceID = UUID()
        let leaf1 = SurfaceLeaf()
        let leaf2 = SurfaceLeaf(surfaceID: surfaceID)
        let root = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(leaf1), second: .leaf(leaf2)
        ))

        let found = SplitTree.findLeaf(node: root, surfaceID: surfaceID)
        #expect(found?.id == leaf2.id)

        let notFound = SplitTree.findLeaf(node: root, surfaceID: UUID())
        #expect(notFound == nil)
    }

    @Test func closeInNestedTree() {
        let leaf1 = SurfaceLeaf()
        let leaf2 = SurfaceLeaf()
        let leaf3 = SurfaceLeaf()

        // Tree: (leaf1 | (leaf2 / leaf3))
        let inner = SplitBranch(
            orientation: .vertical,
            first: .leaf(leaf2), second: .leaf(leaf3)
        )
        let root = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(leaf1), second: .split(inner)
        ))

        // Close leaf2 -- inner branch collapses to leaf3
        let result = SplitTree.close(node: root, leafID: leaf2.id)

        guard case .split(let branch) = result else {
            Issue.record("Expected branch after partial close")
            return
        }
        let leaves = SplitTree.allLeaves(node: .split(branch))
        #expect(leaves.count == 2)
        #expect(leaves.map(\.id) == [leaf1.id, leaf3.id])
    }

    // MARK: - Spatial navigation

    @Test func findNeighborLeft() {
        // horizontal(A, B) -- from B, go left -> A
        let leafA = SurfaceLeaf()
        let leafB = SurfaceLeaf()
        let root = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(leafA), second: .leaf(leafB)
        ))

        let result = SplitTree.findNeighbor(
            node: root, leafID: leafB.id, direction: .left)
        #expect(result?.id == leafA.id)
    }

    @Test func findNeighborRight() {
        // horizontal(A, B) -- from A, go right -> B
        let leafA = SurfaceLeaf()
        let leafB = SurfaceLeaf()
        let root = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(leafA), second: .leaf(leafB)
        ))

        let result = SplitTree.findNeighbor(
            node: root, leafID: leafA.id, direction: .right)
        #expect(result?.id == leafB.id)
    }

    @Test func findNeighborUp() {
        // vertical(A, B) -- from B, go up -> A
        let leafA = SurfaceLeaf()
        let leafB = SurfaceLeaf()
        let root = SplitNode.split(SplitBranch(
            orientation: .vertical,
            first: .leaf(leafA), second: .leaf(leafB)
        ))

        let result = SplitTree.findNeighbor(
            node: root, leafID: leafB.id, direction: .up)
        #expect(result?.id == leafA.id)
    }

    @Test func findNeighborDown() {
        // vertical(A, B) -- from A, go down -> B
        let leafA = SurfaceLeaf()
        let leafB = SurfaceLeaf()
        let root = SplitNode.split(SplitBranch(
            orientation: .vertical,
            first: .leaf(leafA), second: .leaf(leafB)
        ))

        let result = SplitTree.findNeighbor(
            node: root, leafID: leafA.id, direction: .down)
        #expect(result?.id == leafB.id)
    }

    @Test func findNeighborAcrossBranches() {
        // Tree: horizontal(vertical(A, B), C)
        // From C, go left -> B (rightmost in left subtree)
        let leafA = SurfaceLeaf()
        let leafB = SurfaceLeaf()
        let leafC = SurfaceLeaf()
        let left = SplitBranch(
            orientation: .vertical,
            first: .leaf(leafA), second: .leaf(leafB)
        )
        let root = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .split(left), second: .leaf(leafC)
        ))

        let result = SplitTree.findNeighbor(
            node: root, leafID: leafC.id, direction: .left)
        #expect(result?.id == leafB.id)
    }

    @Test func findNeighborReturnsNilAtEdge() {
        // horizontal(A, B) -- from A, go left -> nil (already leftmost)
        let leafA = SurfaceLeaf()
        let leafB = SurfaceLeaf()
        let root = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(leafA), second: .leaf(leafB)
        ))

        let result = SplitTree.findNeighbor(
            node: root, leafID: leafA.id, direction: .left)
        #expect(result == nil)
    }

    @Test func findNeighborUpAcrossBranches() {
        // Tree: vertical(horizontal(A, B), horizontal(C, D))
        // From D, go up -> B (bottommost in top subtree, rightmost)
        let leafA = SurfaceLeaf()
        let leafB = SurfaceLeaf()
        let leafC = SurfaceLeaf()
        let leafD = SurfaceLeaf()
        let top = SplitBranch(
            orientation: .horizontal,
            first: .leaf(leafA), second: .leaf(leafB)
        )
        let bottom = SplitBranch(
            orientation: .horizontal,
            first: .leaf(leafC), second: .leaf(leafD)
        )
        let root = SplitNode.split(SplitBranch(
            orientation: .vertical,
            first: .split(top), second: .split(bottom)
        ))

        let result = SplitTree.findNeighbor(
            node: root, leafID: leafD.id, direction: .up)
        #expect(result?.id == leafB.id)
    }

    @Test func findNeighborDownFromTopLeft() {
        // Tree: vertical(horizontal(A, B), horizontal(C, D))
        // From A, go down -> C (topmost in bottom subtree, leftmost)
        let leafA = SurfaceLeaf()
        let leafB = SurfaceLeaf()
        let leafC = SurfaceLeaf()
        let leafD = SurfaceLeaf()
        let top = SplitBranch(
            orientation: .horizontal,
            first: .leaf(leafA), second: .leaf(leafB)
        )
        let bottom = SplitBranch(
            orientation: .horizontal,
            first: .leaf(leafC), second: .leaf(leafD)
        )
        let root = SplitNode.split(SplitBranch(
            orientation: .vertical,
            first: .split(top), second: .split(bottom)
        ))

        let result = SplitTree.findNeighbor(
            node: root, leafID: leafA.id, direction: .down)
        #expect(result?.id == leafC.id)
    }

    @Test func findNeighborRightMatchesPerpendicularPosition() {
        // Tree: horizontal(vertical(A, C), vertical(B, D))
        //   A | B
        //   --+--
        //   C | D
        // From C (bottom-left), go right -> D (bottom-right, not B)
        let leafA = SurfaceLeaf()
        let leafB = SurfaceLeaf()
        let leafC = SurfaceLeaf()
        let leafD = SurfaceLeaf()
        let left = SplitBranch(
            orientation: .vertical,
            first: .leaf(leafA), second: .leaf(leafC)
        )
        let right = SplitBranch(
            orientation: .vertical,
            first: .leaf(leafB), second: .leaf(leafD)
        )
        let root = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .split(left), second: .split(right)
        ))

        let result = SplitTree.findNeighbor(
            node: root, leafID: leafC.id, direction: .right)
        #expect(result?.id == leafD.id)
    }

    @Test func findNeighborLeftMatchesPerpendicularPosition() {
        // Same tree as above, from D (bottom-right), go left -> C (bottom-left)
        let leafA = SurfaceLeaf()
        let leafB = SurfaceLeaf()
        let leafC = SurfaceLeaf()
        let leafD = SurfaceLeaf()
        let left = SplitBranch(
            orientation: .vertical,
            first: .leaf(leafA), second: .leaf(leafC)
        )
        let right = SplitBranch(
            orientation: .vertical,
            first: .leaf(leafB), second: .leaf(leafD)
        )
        let root = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .split(left), second: .split(right)
        ))

        let result = SplitTree.findNeighbor(
            node: root, leafID: leafD.id, direction: .left)
        #expect(result?.id == leafC.id)
    }

    // MARK: - Directional split creation

    @Test func splitDirectionLeft() {
        // Splitting left: new pane becomes first child
        let leaf = SurfaceLeaf()
        let root = SplitNode.leaf(leaf)
        let newLeafID = UUID()

        let result = SplitTree.split(
            node: root, leafID: leaf.id,
            direction: .left, newLeafID: newLeafID
        )

        guard case .split(let branch) = result else {
            Issue.record("Expected split branch")
            return
        }
        #expect(branch.orientation == .horizontal)
        // New pane is first (left), original is second (right)
        guard case .leaf(let first) = branch.first else {
            Issue.record("Expected leaf")
            return
        }
        #expect(first.id == newLeafID)
        guard case .leaf(let second) = branch.second else {
            Issue.record("Expected leaf")
            return
        }
        #expect(second.id == leaf.id)
    }

    @Test func splitDirectionRight() {
        // Splitting right: original stays first, new goes second (existing behavior)
        let leaf = SurfaceLeaf()
        let root = SplitNode.leaf(leaf)
        let newLeafID = UUID()

        let result = SplitTree.split(
            node: root, leafID: leaf.id,
            direction: .right, newLeafID: newLeafID
        )

        guard case .split(let branch) = result else {
            Issue.record("Expected split branch")
            return
        }
        #expect(branch.orientation == .horizontal)
        // Original is first (left), new is second (right)
        guard case .leaf(let first) = branch.first else {
            Issue.record("Expected leaf")
            return
        }
        #expect(first.id == leaf.id)
        guard case .leaf(let second) = branch.second else {
            Issue.record("Expected leaf")
            return
        }
        #expect(second.id == newLeafID)
    }

    @Test func splitDirectionUp() {
        // Splitting up: new pane becomes first child (top)
        let leaf = SurfaceLeaf()
        let root = SplitNode.leaf(leaf)
        let newLeafID = UUID()

        let result = SplitTree.split(
            node: root, leafID: leaf.id,
            direction: .up, newLeafID: newLeafID
        )

        guard case .split(let branch) = result else {
            Issue.record("Expected split branch")
            return
        }
        #expect(branch.orientation == .vertical)
        guard case .leaf(let first) = branch.first else {
            Issue.record("Expected leaf")
            return
        }
        #expect(first.id == newLeafID)
    }

    @Test func splitDirectionDown() {
        // Splitting down: original stays first (top), new goes second (bottom)
        let leaf = SurfaceLeaf()
        let root = SplitNode.leaf(leaf)
        let newLeafID = UUID()

        let result = SplitTree.split(
            node: root, leafID: leaf.id,
            direction: .down, newLeafID: newLeafID
        )

        guard case .split(let branch) = result else {
            Issue.record("Expected split branch")
            return
        }
        #expect(branch.orientation == .vertical)
        guard case .leaf(let first) = branch.first else {
            Issue.record("Expected leaf")
            return
        }
        #expect(first.id == leaf.id)
    }
}
