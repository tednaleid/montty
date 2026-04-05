import Foundation

struct MinimapRect: Equatable {
    let originX: Double
    let originY: Double
    let width: Double
    let height: Double
}

struct MinimapPane: Equatable {
    let leafID: UUID
    let surfaceID: UUID
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
        surfaceTitles: [UUID: String] = [:],
        claudeStates: [String: ClaudeCodeStatus.State] = [:],
        surfaceToMonttyID: [UUID: String] = [:]
    ) -> SplitMinimap {
        let ctx = LayoutContext(
            focusedLeafID: focusedLeafID, surfaceTitles: surfaceTitles,
            claudeStates: claudeStates, surfaceToMonttyID: surfaceToMonttyID
        )
        var panes: [MinimapPane] = []
        layoutNode(node, rect: MinimapRect(originX: 0, originY: 0, width: 1, height: 1),
                   ctx: ctx, panes: &panes)
        return SplitMinimap(panes: panes)
    }

    private struct LayoutContext {
        let focusedLeafID: UUID?
        let surfaceTitles: [UUID: String]
        let claudeStates: [String: ClaudeCodeStatus.State]
        let surfaceToMonttyID: [UUID: String]
    }

    private static func layoutNode(
        _ node: SplitNode, rect: MinimapRect,
        ctx: LayoutContext, panes: inout [MinimapPane]
    ) {
        switch node {
        case .leaf(let leaf):
            // Claude state comes exclusively from hook events routed by MONTTY_SURFACE_ID.
            let claude: ClaudeCodeStatus?
            if let monttyID = ctx.surfaceToMonttyID[leaf.surfaceID],
               let hookState = ctx.claudeStates[monttyID] {
                let sessionName = ctx.surfaceTitles[leaf.surfaceID] ?? "Claude Code"
                claude = ClaudeCodeStatus(sessionName: sessionName, state: hookState)
            } else {
                claude = nil
            }
            panes.append(MinimapPane(
                leafID: leaf.id, surfaceID: leaf.surfaceID, rect: rect,
                isFocused: leaf.id == ctx.focusedLeafID, claudeCode: claude
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

            layoutNode(branch.first, rect: firstRect, ctx: ctx, panes: &panes)
            layoutNode(branch.second, rect: secondRect, ctx: ctx, panes: &panes)
        }
    }
}
