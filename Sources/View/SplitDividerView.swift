import SwiftUI

struct SplitDividerView<First: View, Second: View>: View {
    let orientation: SplitOrientation
    @Binding var ratio: CGFloat
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second

    private let dividerSize: CGFloat = 6
    private let minRatio: CGFloat = 0.1
    private let maxRatio: CGFloat = 0.9

    var body: some View {
        GeometryReader { geo in
            let totalSize = orientation == .horizontal
                ? geo.size.width : geo.size.height

            if orientation == .horizontal {
                HStack(spacing: 0) {
                    first()
                        .frame(width: max(0, totalSize * ratio - dividerSize / 2))
                    dividerBar(totalSize: totalSize)
                    second()
                        .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    first()
                        .frame(height: max(0, totalSize * ratio - dividerSize / 2))
                    dividerBar(totalSize: totalSize)
                    second()
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }

    private func dividerBar(totalSize: CGFloat) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(
                width: orientation == .horizontal ? dividerSize : nil,
                height: orientation == .vertical ? dividerSize : nil
            )
            .contentShape(Rectangle())
            .cursor(orientation == .horizontal ? .resizeLeftRight : .resizeUpDown)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let position = orientation == .horizontal
                            ? value.location.x : value.location.y
                        // Position is relative to the divider, offset by
                        // the first pane's size
                        let firstSize = totalSize * ratio
                        let newFirstSize = firstSize + position - dividerSize / 2
                        let newRatio = newFirstSize / totalSize
                        ratio = min(maxRatio, max(minRatio, newRatio))
                    }
            )
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
