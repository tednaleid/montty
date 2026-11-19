// ABOUTME: Where a dragged tab will land: which gap between sidebar rows the cursor is
// ABOUTME: over, and the index the tab ends up at once it moves there.

import Foundation

/// A gap is numbered by the row beneath it, so gap 0 is above the first row and
/// gap `count` is below the last. The sidebar draws its insertion line at a gap
/// and drops at the index this works out for it.
enum TabDropTarget {
    /// The gap the cursor is nearest while over `row`: the one above it in the
    /// row's upper half, the one below it in the lower half.
    static func gap(overRow row: Int, lowerHalf: Bool) -> Int {
        lowerHalf ? row + 1 : row
    }

    /// The index the dragged tab ends up at when dropped in `gap`, or nil when
    /// that would leave it where it is, so the sidebar shows no line for it.
    ///
    /// `draggedIndex` is the tab's index in this window, or nil when it comes
    /// from another window. A tab already here leaves its old spot first, so a
    /// gap below it is one index too high once it has gone.
    static func landingIndex(gap: Int, draggedIndex: Int?) -> Int? {
        guard let draggedIndex else { return gap }
        let landing = gap > draggedIndex ? gap - 1 : gap
        return landing == draggedIndex ? nil : landing
    }
}
