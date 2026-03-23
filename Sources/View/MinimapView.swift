import SwiftUI

struct MinimapView: View {
    let minimap: SplitMinimap
    let tabColor: Color
    let isActiveTab: Bool

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
                    if let claude = pane.claudeCode {
                        ClaudeIndicatorView(state: claude.state)
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
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

    private func paneFill(_ pane: MinimapPane) -> Color {
        if pane.isFocused {
            return tabColor.opacity(isActiveTab ? 0.45 : 0.3)
        }
        return tabColor.opacity(isActiveTab ? 0.2 : 0.12)
    }

    private func paneBorder(_ pane: MinimapPane) -> Color {
        if pane.isFocused {
            return tabColor.opacity(isActiveTab ? 0.9 : 0.5)
        }
        return tabColor.opacity(isActiveTab ? 0.45 : 0.25)
    }
}

/// Animated indicator for Claude Code state on a minimap pane.
struct ClaudeIndicatorView: View {
    let state: ClaudeCodeStatus.State

    // Cycle through star characters when working
    private static let thinkingChars: [String] = ["*", "\u{2736}", "\u{273B}", "\u{2733}", "\u{2722}", "\u{00B7}"]

    @State private var charIndex = 0
    @State private var blinkVisible = true

    var body: some View {
        Group {
            switch state {
            case .working:
                Text(Self.thinkingChars[charIndex % Self.thinkingChars.count])
                    .onAppear { startAnimation() }
            case .waiting:
                Text(blinkVisible ? "*?" : "")
                    .onAppear { startBlink() }
            case .unknown:
                Text("*")
            case .idle:
                EmptyView()
            }
        }
        .font(.system(size: 32, weight: .bold))
        .foregroundStyle(.orange)
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            charIndex = (charIndex + 1) % Self.thinkingChars.count
        }
    }

    private func startBlink() {
        Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            blinkVisible.toggle()
        }
    }
}
