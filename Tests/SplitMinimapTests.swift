import Foundation
import Testing
@testable import montty_unit

struct SplitMinimapTests {
    @Test func singleLeafProducesOnePane() {
        let leaf = SurfaceLeaf()
        let minimap = SplitMinimap.from(
            node: .leaf(leaf), focusedLeafID: leaf.id
        )
        #expect(minimap.panes.count == 1)
        let pane = minimap.panes[0]
        #expect(pane.leafID == leaf.id)
        #expect(pane.rect.originX == 0)
        #expect(pane.rect.originY == 0)
        #expect(pane.rect.width == 1)
        #expect(pane.rect.height == 1)
        #expect(pane.isFocused == true)
    }

    @Test func horizontalSplitProducesTwoPanes() {
        let left = SurfaceLeaf()
        let right = SurfaceLeaf()
        let node = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(left),
            second: .leaf(right)
        ))
        let minimap = SplitMinimap.from(node: node, focusedLeafID: left.id)
        #expect(minimap.panes.count == 2)

        let leftPane = minimap.panes[0]
        #expect(leftPane.leafID == left.id)
        #expect(leftPane.rect.originX == 0)
        #expect(leftPane.rect.width == 0.5)
        #expect(leftPane.rect.height == 1)

        let rightPane = minimap.panes[1]
        #expect(rightPane.leafID == right.id)
        #expect(rightPane.rect.originX == 0.5)
        #expect(rightPane.rect.width == 0.5)
    }

    @Test func verticalSplitProducesTwoPanes() {
        let top = SurfaceLeaf()
        let bottom = SurfaceLeaf()
        let node = SplitNode.split(SplitBranch(
            orientation: .vertical,
            first: .leaf(top),
            second: .leaf(bottom)
        ))
        let minimap = SplitMinimap.from(node: node, focusedLeafID: nil)
        #expect(minimap.panes.count == 2)

        let topPane = minimap.panes[0]
        #expect(topPane.rect.originY == 0)
        #expect(topPane.rect.height == 0.5)
        #expect(topPane.rect.width == 1)

        let bottomPane = minimap.panes[1]
        #expect(bottomPane.rect.originY == 0.5)
        #expect(bottomPane.rect.height == 0.5)
    }

    @Test func customRatioAffectsLayout() {
        let first = SurfaceLeaf()
        let second = SurfaceLeaf()
        let node = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            ratio: 0.3,
            first: .leaf(first),
            second: .leaf(second)
        ))
        let minimap = SplitMinimap.from(node: node, focusedLeafID: nil)

        let firstPane = minimap.panes[0]
        #expect(abs(firstPane.rect.width - 0.3) < 0.001)

        let secondPane = minimap.panes[1]
        #expect(abs(secondPane.rect.originX - 0.3) < 0.001)
        #expect(abs(secondPane.rect.width - 0.7) < 0.001)
    }

    @Test func nestedSplitProducesThreePanes() {
        // Layout: A | (B / C)
        let leafA = SurfaceLeaf()
        let leafB = SurfaceLeaf()
        let leafC = SurfaceLeaf()
        let node = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(leafA),
            second: .split(SplitBranch(
                orientation: .vertical,
                first: .leaf(leafB),
                second: .leaf(leafC)
            ))
        ))
        let minimap = SplitMinimap.from(node: node, focusedLeafID: leafB.id)
        #expect(minimap.panes.count == 3)

        // A: left half
        #expect(minimap.panes[0].leafID == leafA.id)
        #expect(minimap.panes[0].rect.width == 0.5)
        #expect(minimap.panes[0].rect.height == 1)

        // B: top-right quarter
        #expect(minimap.panes[1].leafID == leafB.id)
        #expect(minimap.panes[1].rect.originX == 0.5)
        #expect(minimap.panes[1].rect.width == 0.5)
        #expect(minimap.panes[1].rect.height == 0.5)
        #expect(minimap.panes[1].isFocused == true)

        // C: bottom-right quarter
        #expect(minimap.panes[2].leafID == leafC.id)
        #expect(minimap.panes[2].rect.originX == 0.5)
        #expect(minimap.panes[2].rect.originY == 0.5)
    }

    @Test func focusedPaneIsMarked() {
        let left = SurfaceLeaf()
        let right = SurfaceLeaf()
        let node = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(left),
            second: .leaf(right)
        ))
        let minimap = SplitMinimap.from(node: node, focusedLeafID: right.id)

        #expect(minimap.panes[0].isFocused == false)
        #expect(minimap.panes[1].isFocused == true)
    }

    @Test func noFocusedLeafAllUnfocused() {
        let left = SurfaceLeaf()
        let right = SurfaceLeaf()
        let node = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(left),
            second: .leaf(right)
        ))
        let minimap = SplitMinimap.from(node: node, focusedLeafID: nil)

        #expect(minimap.panes[0].isFocused == false)
        #expect(minimap.panes[1].isFocused == false)
    }

    // MARK: - Claude Code detection per pane

    @Test func paneDetectsClaudeCodeFromTitle() {
        let left = SurfaceLeaf()
        let right = SurfaceLeaf()
        let node = SplitNode.split(SplitBranch(
            orientation: .horizontal,
            first: .leaf(left),
            second: .leaf(right)
        ))
        // Only the right pane is running Claude Code
        let titles: [UUID: String] = [
            left.surfaceID: "zsh",
            right.surfaceID: "✳ Fix auth bug"
        ]
        let minimap = SplitMinimap.from(
            node: node, focusedLeafID: nil, surfaceTitles: titles
        )
        #expect(minimap.panes[0].claudeCode == nil)
        #expect(minimap.panes[1].claudeCode != nil)
        #expect(minimap.panes[1].claudeCode?.sessionName == "Fix auth bug")
    }

    @Test func paneWithNoTitlesHasNoClaudeCode() {
        let leaf = SurfaceLeaf()
        let minimap = SplitMinimap.from(node: .leaf(leaf), focusedLeafID: nil)
        #expect(minimap.panes[0].claudeCode == nil)
    }
}
