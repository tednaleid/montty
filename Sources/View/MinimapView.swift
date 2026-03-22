import SwiftUI

struct MinimapView: View {
    let minimap: SplitMinimap
    let tabColor: Color
    let isActiveTab: Bool

    private let gapSize: CGFloat = 1
    private let cornerRadius: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ForEach(minimap.panes, id: \.leafID) { pane in
                let frame = paneFrame(pane.rect, in: size)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(paneFill(pane))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(paneBorder(pane), lineWidth: pane.isFocused ? 1.5 : 0.5)
                    )
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(height: 60)
    }

    private func paneFrame(_ rect: MinimapRect, in size: CGSize) -> CGRect {
        let totalGapX = gapSize * CGFloat(max(0, horizontalPaneCount() - 1))
        let totalGapY = gapSize * CGFloat(max(0, verticalPaneCount() - 1))
        let availW = size.width - totalGapX
        let availH = size.height - totalGapY

        return CGRect(
            x: CGFloat(rect.originX) * availW + CGFloat(rect.originX) * totalGapX,
            y: CGFloat(rect.originY) * availH + CGFloat(rect.originY) * totalGapY,
            width: CGFloat(rect.width) * availW,
            height: CGFloat(rect.height) * availH
        )
    }

    private func paneFill(_ pane: MinimapPane) -> Color {
        if pane.isFocused {
            return tabColor.opacity(isActiveTab ? 0.4 : 0.25)
        }
        return tabColor.opacity(isActiveTab ? 0.15 : 0.1)
    }

    private func paneBorder(_ pane: MinimapPane) -> Color {
        if pane.isFocused {
            return tabColor.opacity(isActiveTab ? 0.9 : 0.5)
        }
        return tabColor.opacity(isActiveTab ? 0.3 : 0.15)
    }

    // Rough count of distinct horizontal positions for gap calculation
    private func horizontalPaneCount() -> Int {
        let origins = Set(minimap.panes.map { Int($0.rect.originX * 100) })
        return origins.count
    }

    private func verticalPaneCount() -> Int {
        let origins = Set(minimap.panes.map { Int($0.rect.originY * 100) })
        return origins.count
    }
}
