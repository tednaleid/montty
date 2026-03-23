import Foundation
import Testing
@testable import montty_unit

@Suite struct JumpLabelGenerationTests {
    @Test func singleTarget() {
        let labels = JumpLabels.generateLabels(count: 1)
        #expect(labels == ["a"])
    }

    @Test func fiveTargets() {
        let labels = JumpLabels.generateLabels(count: 5)
        #expect(labels == ["a", "b", "c", "d", "e"])
    }

    @Test func twentySixTargetsAllSingleChar() {
        let labels = JumpLabels.generateLabels(count: 26)
        #expect(labels.count == 26)
        #expect(labels.first == "a")
        #expect(labels.last == "z")
        #expect(labels.allSatisfy { $0.count == 1 })
    }

    @Test func twentySevenTargetsMixesSingleAndDouble() {
        let labels = JumpLabels.generateLabels(count: 27)
        #expect(labels.count == 27)
        // P = ceil((27-26)/25) = 1, singleCount = 25
        // Single: b-z (25 labels), Double: aa, ab (2 labels, but we need 2)
        let singleLabels = labels.filter { $0.count == 1 }
        let doubleLabels = labels.filter { $0.count == 2 }
        #expect(singleLabels.count == 25)
        #expect(doubleLabels.count == 2)
        // Double labels use 'a' as prefix (reserved)
        #expect(doubleLabels.allSatisfy { $0.hasPrefix("a") })
    }

    @Test func fiftyTwoTargets() {
        let labels = JumpLabels.generateLabels(count: 52)
        #expect(labels.count == 52)
        // P = ceil((52-26)/25) = ceil(1.04) = 2, singleCount = 24
        let singleLabels = labels.filter { $0.count == 1 }
        let doubleLabels = labels.filter { $0.count == 2 }
        #expect(singleLabels.count == 24)
        #expect(doubleLabels.count == 28)
    }

    @Test func zeroTargets() {
        let labels = JumpLabels.generateLabels(count: 0)
        #expect(labels.isEmpty)
    }

    @Test func allLabelsUnique() {
        for count in [1, 5, 26, 27, 50, 100, 200] {
            let labels = JumpLabels.generateLabels(count: count)
            #expect(Set(labels).count == labels.count,
                    "Duplicate labels for count \(count)")
        }
    }

    @Test func noThreeCharLabels() {
        // Maximum supported: 26 + 26*26 = 702 targets
        let labels = JumpLabels.generateLabels(count: 200)
        #expect(labels.allSatisfy { $0.count <= 2 })
    }
}

@Suite struct JumpLabelAssignmentTests {
    @Test func assignMapsLabelsToTargets() {
        let targets = [
            JumpTarget(tabID: UUID(), leafID: UUID()),
            JumpTarget(tabID: UUID(), leafID: UUID()),
            JumpTarget(tabID: UUID(), leafID: UUID())
        ]
        let state = JumpLabels.assign(targets: targets)
        #expect(state.labelToTarget.count == 3)
        #expect(state.leafToLabel.count == 3)
        #expect(state.buffer == "")
        // First target gets "a"
        #expect(state.leafToLabel[targets[0].leafID] == "a")
        #expect(state.leafToLabel[targets[1].leafID] == "b")
        #expect(state.leafToLabel[targets[2].leafID] == "c")
    }

    @Test func assignEmptyTargets() {
        let state = JumpLabels.assign(targets: [])
        #expect(state.labelToTarget.isEmpty)
        #expect(state.leafToLabel.isEmpty)
        #expect(state.prefixes.isEmpty)
    }

    @Test func assignSetsPrefixes() {
        // 27 targets: 25 single (b-z) + 2 double (aa, ab)
        let targets = (0..<27).map { _ in
            JumpTarget(tabID: UUID(), leafID: UUID())
        }
        let state = JumpLabels.assign(targets: targets)
        #expect(state.prefixes.contains("a"))
        #expect(state.prefixes.count == 1)
    }
}

@Suite struct JumpStateInputTests {
    @Test func singleCharMatchJumps() {
        let target = JumpTarget(tabID: UUID(), leafID: UUID())
        let state = JumpLabels.assign(targets: [target])
        let (newState, found) = JumpLabels.handleKey("a", state: state)
        #expect(newState == nil) // jump mode ends
        #expect(found == target)
    }

    @Test func invalidKeyCancel() {
        let target = JumpTarget(tabID: UUID(), leafID: UUID())
        let state = JumpLabels.assign(targets: [target])
        let (newState, found) = JumpLabels.handleKey("z", state: state)
        #expect(newState == nil) // jump mode ends
        #expect(found == nil)   // no target
    }

    @Test func prefixBuffersThenMatches() {
        // 27 targets: 'a' is a prefix letter
        let targets = (0..<27).map { _ in
            JumpTarget(tabID: UUID(), leafID: UUID())
        }
        let state = JumpLabels.assign(targets: targets)

        // Press 'a' -- should buffer as prefix
        let (afterA, targetA) = JumpLabels.handleKey("a", state: state)
        #expect(afterA != nil)
        #expect(afterA?.buffer == "a")
        #expect(targetA == nil)

        // Press 'a' again -- should match "aa"
        let (afterAA, targetAA) = JumpLabels.handleKey("a", state: afterA!)
        #expect(afterAA == nil) // jump mode ends
        #expect(targetAA != nil) // found target
    }

    @Test func prefixThenInvalidCancels() {
        let targets = (0..<27).map { _ in
            JumpTarget(tabID: UUID(), leafID: UUID())
        }
        let state = JumpLabels.assign(targets: targets)

        // Press 'a' (valid prefix)
        let (afterA, _) = JumpLabels.handleKey("a", state: state)
        #expect(afterA != nil)

        // Only 2 double labels (aa, ab), so 'c' after 'a' is invalid
        let (afterAC, targetAC) = JumpLabels.handleKey("c", state: afterA!)
        #expect(afterAC == nil)
        #expect(targetAC == nil)
    }
}
