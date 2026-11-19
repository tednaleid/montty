// ABOUTME: Verifies how a cursor position over the sidebar becomes an insertion gap, and
// ABOUTME: how a gap becomes the dragged tab's final index (or nothing, when it would not move).

import Testing
@testable import montty_unit

struct TabDropTargetTests {
    @Test func theUpperHalfOfARowIsTheGapAboveIt() {
        #expect(TabDropTarget.gap(overRow: 2, lowerHalf: false) == 2)
    }

    @Test func theLowerHalfOfARowIsTheGapBelowIt() {
        #expect(TabDropTarget.gap(overRow: 2, lowerHalf: true) == 3)
    }

    /// A tab from another window removes nothing from this one, so the gap is
    /// the index it lands at.
    @Test func aTabFromAnotherWindowLandsAtTheGap() {
        #expect(TabDropTarget.landingIndex(gap: 0, draggedIndex: nil) == 0)
        #expect(TabDropTarget.landingIndex(gap: 3, draggedIndex: nil) == 3)
    }

    @Test func movingUpLandsAtTheGap() {
        // Tabs a b c d; drag d (3) into the gap above b (1): a d b c.
        #expect(TabDropTarget.landingIndex(gap: 1, draggedIndex: 3) == 1)
    }

    /// The dragged tab leaves its old spot first, so every row below it shifts up.
    @Test func movingDownLandsOneBelowTheGapIndex() {
        // Tabs a b c d; drag a (0) into the gap above d (3): b c a d, so a lands at 2.
        #expect(TabDropTarget.landingIndex(gap: 3, draggedIndex: 0) == 2)
    }

    @Test func movingToTheEndLandsAtTheLastIndex() {
        // Tabs a b c; drag a (0) into the gap after c (3): b c a.
        #expect(TabDropTarget.landingIndex(gap: 3, draggedIndex: 0) == 2)
    }

    @Test func theGapsOnEitherSideOfTheDraggedTabChangeNothing() {
        #expect(TabDropTarget.landingIndex(gap: 1, draggedIndex: 1) == nil)
        #expect(TabDropTarget.landingIndex(gap: 2, draggedIndex: 1) == nil)
    }

    @Test func theEndGapIsANoOpForTheLastTab() {
        #expect(TabDropTarget.landingIndex(gap: 3, draggedIndex: 2) == nil)
    }

    @Test func theTopGapIsANoOpForTheFirstTab() {
        #expect(TabDropTarget.landingIndex(gap: 0, draggedIndex: 0) == nil)
    }
}
