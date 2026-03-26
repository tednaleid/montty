import SwiftUI

struct SplitContainerView: View {
    let node: SplitNode
    let focusedLeafID: UUID?
    let surfaceLookup: (UUID) -> Ghostty.SurfaceView?
    var jumpLabels: [UUID: String] = [:]
    var surfaceDirectories: [UUID: String] = [:]
    var repoColorOverrides: [String: TabColor] = [:]
    var tabColorOverride: TabColor?
    var surfaceTintEnabled: Bool = true

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
                    surfaceTintEnabled
                        ? surfaceTintColor(for: leaf.surfaceID)
                            .opacity(0.06)
                            .allowsHitTesting(false)
                        : nil
                )
                .overlay(
                    isFocused
                        ? nil
                        : Color.black.opacity(Self.unfocusedDimOpacity)
                            .allowsHitTesting(false)
                )
                .border(isFocused ? borderColor : Color.clear, width: 2)
                .overlay {
                    if let label = jumpLabels[leaf.id] {
                        JumpBadge(label: label, color: surfaceTintColor(for: leaf.surfaceID), large: true)
                    }
                }
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }

    private func surfaceTintColor(for surfaceID: UUID) -> Color {
        if let tabColorOverride { return tabColorOverride.swiftUIColor }
        return TabColor.colorForWorktree(
            surfaceDirectories[surfaceID], overrides: repoColorOverrides
        )?.swiftUIColor ?? .clear
    }

    private var resolvedTabColor: Color {
        if let tabColorOverride { return tabColorOverride.swiftUIColor }
        let dir = focusedLeafID
            .flatMap { leafID in
                SplitTree.allLeaves(node: node)
                    .first { $0.id == leafID }?.surfaceID
            }
            .flatMap { surfaceDirectories[$0] }
        return TabColor.colorForWorktree(
            dir, overrides: repoColorOverrides
        )?.swiftUIColor ?? .gray
    }

    private var borderColor: Color { resolvedTabColor.opacity(0.7) }

    private func branchView(_ branch: SplitBranch) -> some View {
        BranchWrapper(
            branch: branch,
            focusedLeafID: focusedLeafID,
            surfaceLookup: surfaceLookup,
            jumpLabels: jumpLabels,
            surfaceDirectories: surfaceDirectories,
            repoColorOverrides: repoColorOverrides,
            tabColorOverride: tabColorOverride,
            surfaceTintEnabled: surfaceTintEnabled
        )
    }
}

/// Separate struct to hold the @State ratio binding for a branch node.
private struct BranchWrapper: View {
    let branch: SplitBranch
    let focusedLeafID: UUID?
    let surfaceLookup: (UUID) -> Ghostty.SurfaceView?
    var jumpLabels: [UUID: String] = [:]
    var surfaceDirectories: [UUID: String] = [:]
    var repoColorOverrides: [String: TabColor] = [:]
    var tabColorOverride: TabColor?
    var surfaceTintEnabled: Bool = true

    @State private var ratio: CGFloat

    init(
        branch: SplitBranch,
        focusedLeafID: UUID?,
        surfaceLookup: @escaping (UUID) -> Ghostty.SurfaceView?,
        jumpLabels: [UUID: String] = [:],
        surfaceDirectories: [UUID: String] = [:],
        repoColorOverrides: [String: TabColor] = [:],
        tabColorOverride: TabColor? = nil,
        surfaceTintEnabled: Bool = true
    ) {
        self.branch = branch
        self.focusedLeafID = focusedLeafID
        self.surfaceLookup = surfaceLookup
        self.jumpLabels = jumpLabels
        self.surfaceDirectories = surfaceDirectories
        self.repoColorOverrides = repoColorOverrides
        self.tabColorOverride = tabColorOverride
        self.surfaceTintEnabled = surfaceTintEnabled
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
                surfaceLookup: surfaceLookup,
                jumpLabels: jumpLabels,
                surfaceDirectories: surfaceDirectories,
                repoColorOverrides: repoColorOverrides,
                tabColorOverride: tabColorOverride,
                surfaceTintEnabled: surfaceTintEnabled
            )
        } second: {
            SplitContainerView(
                node: branch.second,
                focusedLeafID: focusedLeafID,
                surfaceLookup: surfaceLookup,
                jumpLabels: jumpLabels,
                surfaceDirectories: surfaceDirectories,
                repoColorOverrides: repoColorOverrides,
                tabColorOverride: tabColorOverride,
                surfaceTintEnabled: surfaceTintEnabled
            )
        }
    }
}
