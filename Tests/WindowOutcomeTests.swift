// ABOUTME: Verifies the WindowOutcome value type defaults to doing nothing and
// ABOUTME: compares by value, which is what lets every use-case test assert on it.

import Foundation
import Testing
@testable import montty_unit

@Suite struct WindowOutcomeTests {
    /// A use case that decides nothing must return an outcome the shell can run
    /// safely, so every field defaults to inert.
    @Test func emptyOutcomeAsksForNothing() {
        let outcome = WindowOutcome()

        #expect(outcome.createWindows.isEmpty)
        #expect(outcome.createSurfaces.isEmpty)
        #expect(outcome.destroySurfaces.isEmpty)
        #expect(outcome.closeWindows.isEmpty)
        #expect(outcome.raiseWindow == nil)
        #expect(outcome.applySettings == nil)
        #expect(outcome.save == false)
        #expect(outcome.quit == false)
    }

    /// Every use-case test asserts by comparing outcomes, so equality must
    /// consider the fields rather than identity.
    @Test func outcomesCompareByValue() {
        let id = UUID()
        var first = WindowOutcome()
        first.destroySurfaces = [id]
        first.save = true

        var second = WindowOutcome()
        second.destroySurfaces = [id]
        second.save = true

        #expect(first == second)

        second.save = false
        #expect(first != second)
    }
}
