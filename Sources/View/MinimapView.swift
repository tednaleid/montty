import SwiftUI

struct MinimapView: View {
    let minimap: SplitMinimap
    let tabColor: Color
    let isActiveTab: Bool
    var jumpLabels: [UUID: String] = [:]
    var surfaceDirectories: [UUID: String] = [:]
    var repoColorOverrides: [String: TabColor] = [:]
    var onPaneTap: ((UUID) -> Void)?

    private let gap: CGFloat = 4
    private let cornerRadius: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ForEach(minimap.panes, id: \.leafID) { pane in
                let frame = paneFrame(pane.rect, in: size)
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(paneFill(pane))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .strokeBorder(paneBorder(pane), lineWidth: pane.isFocused ? 1.5 : 0.5)
                        )
                    if let label = jumpLabels[pane.leafID] {
                        JumpBadge(label: label, color: paneColor(pane), large: false)
                    } else if let claude = pane.claudeCode {
                        ClaudeIndicatorView(state: claude.state)
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .onTapGesture {
                    onPaneTap?(pane.leafID)
                }
            }
        }
        .frame(height: 90)
    }

    private func paneFrame(_ rect: MinimapRect, in size: CGSize) -> CGRect {
        // Map normalized 0-1 rect to pixel coordinates, then inset by gap/2
        // so adjacent panes have a consistent gap between them.
        let rawFrame = CGRect(
            x: CGFloat(rect.originX) * size.width,
            y: CGFloat(rect.originY) * size.height,
            width: CGFloat(rect.width) * size.width,
            height: CGFloat(rect.height) * size.height
        )
        return rawFrame.insetBy(dx: gap / 2, dy: gap / 2)
    }

    private func paneColor(_ pane: MinimapPane) -> Color {
        TabColor.colorForWorktree(
            surfaceDirectories[pane.surfaceID], overrides: repoColorOverrides
        )?.swiftUIColor ?? tabColor
    }

    private func paneFill(_ pane: MinimapPane) -> Color {
        let color = paneColor(pane)
        if pane.isFocused {
            return color.opacity(isActiveTab ? 0.45 : 0.3)
        }
        return color.opacity(isActiveTab ? 0.2 : 0.12)
    }

    private func paneBorder(_ pane: MinimapPane) -> Color {
        let color = paneColor(pane)
        if pane.isFocused {
            return color.opacity(isActiveTab ? 0.9 : 0.5)
        }
        return color.opacity(isActiveTab ? 0.45 : 0.25)
    }
}

/// Animated indicator for Claude Code state on a minimap pane.
struct ClaudeIndicatorView: View {
    let state: ClaudeCodeStatus.State

    // Cycle through star characters when working
    private static let thinkingChars: [String] = [
        "*", "\u{2736}", "\u{273B}", "\u{2733}", "\u{2722}", "\u{00B7}"
    ]

    @State private var charIndex = 0
    private let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            switch state {
            case .working:
                Text(Self.thinkingChars[charIndex % Self.thinkingChars.count])
                    .onReceive(timer) { _ in
                        charIndex = (charIndex + 1) % Self.thinkingChars.count
                    }
            case .waiting:
                Text("*?")
            case .idle, .unknown:
                Text("*")
            }
        }
        .font(.system(size: 32))
        .foregroundStyle(.orange)
    }
}
