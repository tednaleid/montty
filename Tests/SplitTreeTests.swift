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
}
