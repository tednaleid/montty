import SwiftUI

struct SplitContainerView: View {
    let node: SplitNode
    let focusedLeafID: UUID?
    let tabColor: TabColor
    let surfaceLookup: (UUID) -> Ghostty.SurfaceView?
    let onFocusLeaf: (UUID) -> Void
    var jumpLabels: [UUID: String] = [:]

    // Tweak this to control how much unfocused panes are dimmed.
    // 0.0 = no dimming, 0.3 = heavy dimming.
    private static let unfocusedDimOpacity: Double = 0.25

    var body: some View {
        switch node {
        case .leaf(let leaf):
            leafView(leaf)

        case .split(let branch):
            branchView(branch)
        }
    }

    @ViewBuilder
    private func leafView(_ leaf: SurfaceLeaf) -> some View {
        let isFocused = leaf.id == focusedLeafID

        if let surfaceView = surfaceLookup(leaf.surfaceID) {
            Ghostty.SurfaceWrapper(surfaceView: surfaceView)
                .overlay(
                    isFocused
                        ? nil
                        : Color.black.opacity(Self.unfocusedDimOpacity)
                            .allowsHitTesting(false)
                )
                .border(isFocused ? borderColor : Color.clear, width: 2)
                .overlay {
                    if let label = jumpLabels[leaf.id] {
                        JumpBadge(label: label, color: badgeColor, large: true)
                    }
                }
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }

    private var badgeColor: Color {
        switch tabColor {
        case .preset(let preset): return preset.swiftUIColor
        case .auto: return .accentColor
        }
    }

    private var borderColor: Color {
        switch tabColor {
        case .preset(let preset):
            return preset.swiftUIColor.opacity(0.7)
        case .auto:
            return Color.accentColor.opacity(0.5)
        }
    }

    private func branchView(_ branch: SplitBranch) -> some View {
        BranchWrapper(
            branch: branch,
            focusedLeafID: focusedLeafID,
            tabColor: tabColor,
            surfaceLookup: surfaceLookup,
            onFocusLeaf: onFocusLeaf,
            jumpLabels: jumpLabels
        )
    }
}

/// Separate struct to hold the @State ratio binding for a branch node.
private struct BranchWrapper: View {
    let branch: SplitBranch
    let focusedLeafID: UUID?
    let tabColor: TabColor
    let surfaceLookup: (UUID) -> Ghostty.SurfaceView?
    let onFocusLeaf: (UUID) -> Void
    var jumpLabels: [UUID: String] = [:]

    @State private var ratio: CGFloat

    init(
        branch: SplitBranch,
        focusedLeafID: UUID?,
        tabColor: TabColor,
        surfaceLookup: @escaping (UUID) -> Ghostty.SurfaceView?,
        onFocusLeaf: @escaping (UUID) -> Void,
        jumpLabels: [UUID: String] = [:]
    ) {
        self.branch = branch
        self.focusedLeafID = focusedLeafID
        self.tabColor = tabColor
        self.surfaceLookup = surfaceLookup
        self.onFocusLeaf = onFocusLeaf
        self.jumpLabels = jumpLabels
        self._ratio = State(initialValue: branch.ratio)
    }

    var body: some View {
        SplitDividerView(
            orientation: branch.orientation,
            ratio: $ratio
        ) {
            SplitContainerView(
                node: branch.first,
                focusedLeafID: focusedLeafID,
                tabColor: tabColor,
                surfaceLookup: surfaceLookup,
                onFocusLeaf: onFocusLeaf,
                jumpLabels: jumpLabels
            )
        } second: {
            SplitContainerView(
                node: branch.second,
                focusedLeafID: focusedLeafID,
                tabColor: tabColor,
                surfaceLookup: surfaceLookup,
                onFocusLeaf: onFocusLeaf,
                jumpLabels: jumpLabels
            )
        }
    }
}
