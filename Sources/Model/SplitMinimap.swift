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
    let claudeCode: ClaudeCodeStatus?
}

struct SplitMinimap: Equatable {
    let panes: [MinimapPane]

    /// Compute minimap layout from a split tree.
    /// Produces normalized 0-1 rects for each leaf pane.
    /// Surface titles are used to detect Claude Code per-pane.
    static func from(
        node: SplitNode,
        focusedLeafID: UUID?,
        surfaceTitles: [UUID: String] = [:]
    ) -> SplitMinimap {
        var panes: [MinimapPane] = []
        layoutNode(node, rect: MinimapRect(originX: 0, originY: 0, width: 1, height: 1),
                   focusedLeafID: focusedLeafID, surfaceTitles: surfaceTitles, panes: &panes)
        return SplitMinimap(panes: panes)
    }

    private static func layoutNode(
        _ node: SplitNode,
        rect: MinimapRect,
        focusedLeafID: UUID?,
        surfaceTitles: [UUID: String],
        panes: inout [MinimapPane]
    ) {
        switch node {
        case .leaf(let leaf):
            let title = surfaceTitles[leaf.surfaceID]
            let claude = title.flatMap { TitleParser.claudeCodeStatus(from: $0) }
            panes.append(MinimapPane(
                leafID: leaf.id,
                rect: rect,
                isFocused: leaf.id == focusedLeafID,
                claudeCode: claude
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

            layoutNode(branch.first, rect: firstRect, focusedLeafID: focusedLeafID,
                       surfaceTitles: surfaceTitles, panes: &panes)
            layoutNode(branch.second, rect: secondRect, focusedLeafID: focusedLeafID,
                       surfaceTitles: surfaceTitles, panes: &panes)
        }
    }
}
