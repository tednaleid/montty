// ABOUTME: Reports where over a sidebar row or the empty area below it a tab is being
// ABOUTME: dragged, so the sidebar can draw an insertion line, and hands over the drop.

import SwiftUI
import UniformTypeIdentifiers

struct TabDropDelegate: DropDelegate {
    /// The gap a cursor at this point, in the coordinates of the view this
    /// delegate is attached to, is nearest.
    let gapAt: (CGPoint) -> Int
    /// The gap the cursor is over, or nil once it has left.
    let onTarget: (Int?) -> Void
    /// The payload was dropped in this gap.
    let onDrop: (NSItemProvider, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.monttyTab])
    }

    func dropEntered(info: DropInfo) {
        onTarget(gapAt(info.location))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onTarget(gapAt(info.location))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onTarget(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        let gap = gapAt(info.location)
        onTarget(nil)
        guard let provider = info.itemProviders(for: [.monttyTab]).first else { return false }
        onDrop(provider, gap)
        return true
    }
}
