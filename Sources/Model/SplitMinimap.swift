import Foundation

struct MinimapRect: Equatable {
    let originX: Double
    let originY: Double
    let width: Double
    let height: Double
}

struct MinimapPane: Equatable {
    let leafID: UUID
    let rect: MinimapRect
    let isFocused: Bool
}

struct SplitMinimap: Equatable {
    let panes: [MinimapPane]

    /// Compute minimap layout from a split tree.
    /// Produces normalized 0-1 rects for each leaf pane.
    static func from(node: SplitNode, focusedLeafID: UUID?) -> SplitMinimap {
        var panes: [MinimapPane] = []
        layoutNode(node, rect: MinimapRect(originX: 0, originY: 0, width: 1, height: 1),
                   focusedLeafID: focusedLeafID, panes: &panes)
        return SplitMinimap(panes: panes)
    }

    private static func layoutNode(
        _ node: SplitNode,
        rect: MinimapRect,
        focusedLeafID: UUID?,
        panes: inout [MinimapPane]
    ) {
        switch node {
        case .leaf(let leaf):
            panes.append(MinimapPane(
                leafID: leaf.id,
                rect: rect,
                isFocused: leaf.id == focusedLeafID
            ))
        case .split(let branch):
            let ratio = Double(branch.ratio)
            let (firstRect, secondRect): (MinimapRect, MinimapRect)

            switch branch.orientation {
            case .horizontal:
                firstRect = MinimapRect(
                    originX: rect.originX, originY: rect.originY,
                    width: rect.width * ratio, height: rect.height)
                secondRect = MinimapRect(
                    originX: rect.originX + rect.width * ratio, originY: rect.originY,
                    width: rect.width * (1 - ratio), height: rect.height)
            case .vertical:
                firstRect = MinimapRect(
                    originX: rect.originX, originY: rect.originY,
                    width: rect.width, height: rect.height * ratio)
                secondRect = MinimapRect(
                    originX: rect.originX, originY: rect.originY + rect.height * ratio,
                    width: rect.width, height: rect.height * (1 - ratio))
            }

            layoutNode(branch.first, rect: firstRect, focusedLeafID: focusedLeafID, panes: &panes)
            layoutNode(branch.second, rect: secondRect, focusedLeafID: focusedLeafID, panes: &panes)
        }
    }
}
