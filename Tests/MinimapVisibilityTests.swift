// ABOUTME: Verifies minimap visibility: its text form, when a tab's row shows its
// ABOUTME: minimap, how a tab override beats the app-wide value, and menu toggling.

import Foundation
import Testing

@Suite struct MinimapVisibilityTests {
    @Test func aFreshStartShowsMinimapsOnlyForSplitTabs() {
        #expect(MinimapVisibility.default == .when([.split]))
        #expect(AppSettings().minimapVisibility == .default)
        #expect(MinimapSettings().visibility == .default)
        #expect(SessionSnapshot().minimapVisibility == .default)
    }

    private let split = MinimapVisibility.when([.split])
    private let status = MinimapVisibility.when([.status])
    private let either = MinimapVisibility.when([.split, .status])

    @Test func parsesEveryValue() {
        #expect(MinimapVisibility.parse("always") == .always)
        #expect(MinimapVisibility.parse("never") == .never)
        #expect(MinimapVisibility.parse("split") == split)
        #expect(MinimapVisibility.parse("status") == status)
        #expect(MinimapVisibility.parse("split,status") == either)
        #expect(MinimapVisibility.parse("status,split") == either)
    }

    @Test func rejectsWhatIsNotAValue() {
        #expect(MinimapVisibility.parse("") == nil)
        #expect(MinimapVisibility.parse("sometimes") == nil)
        #expect(MinimapVisibility.parse("split,") == nil)
        #expect(MinimapVisibility.parse("split,split") == nil)
        #expect(MinimapVisibility.parse("always,split") == nil)
        #expect(MinimapVisibility.parse("never,status") == nil)
    }

    @Test func textReadsBackAsTheSameValue() {
        for visibility in [.always, .never, split, status, either] {
            #expect(MinimapVisibility.parse(visibility.text) == visibility)
        }
        #expect(either.text == "split,status")
    }

    @Test func alwaysAndNeverIgnoreTheTab() {
        #expect(MinimapVisibility.always.shows(surfaceCount: 1, hasStatus: false))
        #expect(!MinimapVisibility.never.shows(surfaceCount: 3, hasStatus: true))
    }

    @Test func splitConditionHoldsWithMoreThanOneSurface() {
        #expect(!split.shows(surfaceCount: 1, hasStatus: true))
        #expect(split.shows(surfaceCount: 2, hasStatus: false))
    }

    @Test func statusConditionHoldsWithAnyStatus() {
        #expect(!status.shows(surfaceCount: 3, hasStatus: false))
        #expect(status.shows(surfaceCount: 1, hasStatus: true))
    }

    @Test func conditionsCombineWithOr() {
        #expect(!either.shows(surfaceCount: 1, hasStatus: false))
        #expect(either.shows(surfaceCount: 2, hasStatus: false))
        #expect(either.shows(surfaceCount: 1, hasStatus: true))
    }

    @Test func togglingFromAlwaysOrNeverLeavesTheOneCondition() {
        #expect(MinimapVisibility.always.toggling(.split) == split)
        #expect(MinimapVisibility.never.toggling(.status) == status)
    }

    @Test func togglingAddsAndRemovesConditions() {
        #expect(split.toggling(.status) == either)
        #expect(either.toggling(.split) == status)
    }

    @Test func togglingOffTheLastConditionLeavesNever() {
        #expect(split.toggling(.split) == .never)
    }

    @Test func encodesAsItsText() throws {
        let data = try JSONEncoder().encode([either])
        #expect(String(data: data, encoding: .utf8) == #"["split,status"]"#)
        #expect(try JSONDecoder().decode([MinimapVisibility].self, from: data) == [either])
    }
}

@Suite struct TabShowsMinimapTests {
    /// A tab with `surfaces` surfaces, each registered under a montty id
    /// "M0", "M1", ... in tree order.
    private func tab(surfaces: Int) -> Tab {
        let tab = Tab()
        for _ in 1..<surfaces {
            tab.splitRoot = SplitTree.split(
                node: tab.splitRoot,
                leafID: SplitTree.allLeaves(node: tab.splitRoot)[0].id,
                direction: .right,
                newLeafID: UUID(),
                newSurfaceID: UUID()
            )
        }
        for (index, surfaceID) in tab.allSurfaceIDs.enumerated() {
            tab.surfaceToMonttyID[surfaceID] = "M\(index)"
        }
        return tab
    }

    @Test func followsTheGlobalValueWithoutAnOverride() {
        let subject = tab(surfaces: 1)
        #expect(subject.showsMinimap(global: .always))
        #expect(!subject.showsMinimap(global: .never))
    }

    @Test func overrideBeatsTheGlobalValue() {
        let subject = tab(surfaces: 1)
        subject.minimapVisibility = .never
        #expect(!subject.showsMinimap(global: .always))
        subject.minimapVisibility = .always
        #expect(subject.showsMinimap(global: .never))
    }

    @Test func clearingTheOverrideFallsBackToTheGlobalValue() {
        let subject = tab(surfaces: 1)
        subject.minimapVisibility = .never
        subject.minimapVisibility = nil
        #expect(subject.showsMinimap(global: .always))
    }

    @Test func splitConditionCountsTheTabsSurfaces() {
        #expect(!tab(surfaces: 1).showsMinimap(global: .when([.split])))
        #expect(tab(surfaces: 2).showsMinimap(global: .when([.split])))
    }

    @Test(arguments: [ActivityStatus.State.working, .waiting, .idle])
    func statusConditionCountsEveryState(state: ActivityStatus.State) {
        let subject = tab(surfaces: 2)
        #expect(!subject.showsMinimap(global: .when([.status])))
        subject.activityStates["M1"] = state
        #expect(subject.showsMinimap(global: .when([.status])))
    }

    @Test func aStatusLeftBehindByAClosedSurfaceDoesNotCount() {
        let subject = tab(surfaces: 1)
        subject.activityStates["gone"] = .working
        #expect(!subject.showsMinimap(global: .when([.status])))
    }
}

@Suite struct TabTintStrengthTests {
    private func opacity(_ base: Double, active: Bool, minimap: Bool) -> Double {
        TabTintStrength.opacity(base: base, isActive: active, showsMinimap: minimap)
    }

    private func isClose(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 0.0001
    }

    @Test func theDefaultGivesEachKindOfRowItsStrength() {
        let base = TabTintStrength.default
        #expect(isClose(opacity(base, active: false, minimap: true), 0.12))
        #expect(isClose(opacity(base, active: true, minimap: true), 0.15))
        #expect(isClose(opacity(base, active: false, minimap: false), 0.20))
        #expect(isClose(opacity(base, active: true, minimap: false), 0.40))
    }

    @Test func zeroTurnsTheWashOff() {
        #expect(opacity(0, active: true, minimap: false) == 0)
        #expect(opacity(0, active: false, minimap: true) == 0)
    }

    @Test func theStrongestRowAtTheTopOfTheRangeIsFullyOpaqueAndNoMore() {
        let top = TabTintStrength.range.upperBound
        #expect(isClose(opacity(top, active: true, minimap: false), 1))
        #expect(opacity(top, active: true, minimap: false) <= 1)
    }
}
