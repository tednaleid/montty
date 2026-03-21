import SwiftUI

struct SplitContainerView: View {
    let node: SplitNode
    let focusedLeafID: UUID?
    let surfaceLookup: (UUID) -> Ghostty.SurfaceView?
    let onFocusLeaf: (UUID) -> Void

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
        if let surfaceView = surfaceLookup(leaf.surfaceID) {
            Ghostty.SurfaceWrapper(surfaceView: surfaceView)
                .border(
                    leaf.id == focusedLeafID
                        ? Color.accentColor.opacity(0.5) : Color.clear,
                    width: 2
                )
                .onTapGesture {
                    onFocusLeaf(leaf.id)
                }
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }

    private func branchView(_ branch: SplitBranch) -> some View {
        BranchWrapper(
            branch: branch,
            focusedLeafID: focusedLeafID,
            surfaceLookup: surfaceLookup,
            onFocusLeaf: onFocusLeaf
        )
    }
}

/// Separate struct to hold the @State ratio binding for a branch node.
private struct BranchWrapper: View {
    let branch: SplitBranch
    let focusedLeafID: UUID?
    let surfaceLookup: (UUID) -> Ghostty.SurfaceView?
    let onFocusLeaf: (UUID) -> Void

    @State private var ratio: CGFloat

    init(
        branch: SplitBranch,
        focusedLeafID: UUID?,
        surfaceLookup: @escaping (UUID) -> Ghostty.SurfaceView?,
        onFocusLeaf: @escaping (UUID) -> Void
    ) {
        self.branch = branch
        self.focusedLeafID = focusedLeafID
        self.surfaceLookup = surfaceLookup
        self.onFocusLeaf = onFocusLeaf
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
                onFocusLeaf: onFocusLeaf
            )
        } second: {
            SplitContainerView(
                node: branch.second,
                focusedLeafID: focusedLeafID,
                surfaceLookup: surfaceLookup,
                onFocusLeaf: onFocusLeaf
            )
        }
    }
}
