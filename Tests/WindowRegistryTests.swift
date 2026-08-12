// ABOUTME: Verifies the registry tracks windows in order, routes a surface to
// ABOUTME: the window and tab that own it, and keeps a key window that exists.

import Foundation
import Testing

@Suite struct WindowRegistryTests {
    private func tabHolding(_ surfaceID: UUID) -> Tab {
        let tab = Tab(id: UUID(), name: "", position: 0)
        tab.splitRoot = .leaf(SurfaceLeaf(id: UUID(), surfaceID: surfaceID))
        return tab
    }

    @Test func addsWindowsInOrderAndMakesTheFirstOneKey() {
        let registry = WindowRegistry()

        let first = registry.add()
        let second = registry.add()

        #expect(registry.windows.map(\.id) == [first.id, second.id])
        #expect(registry.keyWindowID == first.id)
    }

    @Test func routesASurfaceToTheWindowAndTabThatOwnIt() {
        let registry = WindowRegistry()
        registry.add()
        let second = registry.add()
        let surfaceID = UUID()
        let tab = tabHolding(surfaceID)
        second.tabStore.append(tab: tab)

        let found = registry.locate(surfaceID: surfaceID)

        #expect(found?.window.id == second.id)
        #expect(found?.tab.id == tab.id)
    }

    @Test func routesNothingForASurfaceNoWindowOwns() {
        let registry = WindowRegistry()
        registry.add()

        #expect(registry.locate(surfaceID: UUID()) == nil)
    }

    @Test func routesATabIDToTheWindowThatOwnsIt() {
        let registry = WindowRegistry()
        registry.add()
        let second = registry.add()
        let tab = Tab(id: UUID(), name: "", position: 0)
        second.tabStore.append(tab: tab)

        #expect(registry.locate(tabID: tab.id)?.id == second.id)
    }

    @Test func routesNothingForATabIDNoWindowOwns() {
        let registry = WindowRegistry()
        registry.add()

        #expect(registry.locate(tabID: UUID()) == nil)
    }

    @Test func removingAWindowDropsItAndItsSurfaces() {
        let registry = WindowRegistry()
        let only = registry.add()
        let surfaceID = UUID()
        only.tabStore.append(tab: tabHolding(surfaceID))

        registry.remove(id: only.id)

        #expect(registry.windows.isEmpty)
        #expect(registry.locate(surfaceID: surfaceID) == nil)
        #expect(registry.keyWindowID == nil)
    }

    @Test func movesTheKeyPointerWhenTheKeyWindowGoesAway() {
        let registry = WindowRegistry()
        let first = registry.add()
        let second = registry.add()
        registry.keyWindowID = second.id

        registry.remove(id: second.id)

        #expect(registry.keyWindowID == first.id)
        #expect(registry.keyWindow?.id == first.id)
    }

    @Test func leavesTheKeyPointerAloneWhenAnotherWindowCloses() {
        let registry = WindowRegistry()
        let first = registry.add()
        let second = registry.add()
        registry.keyWindowID = second.id

        registry.remove(id: first.id)

        #expect(registry.keyWindowID == second.id)
    }
}
