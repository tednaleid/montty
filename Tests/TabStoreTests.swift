import Foundation
import Testing

struct TabStoreTests {
    @Test func newTabAppendsAtBottom() {
        let store = TabStore()
        let tab1 = Tab(name: "first")
        let tab2 = Tab(name: "second")
        store.append(tab: tab1)
        store.append(tab: tab2)

        #expect(store.tabs.count == 2)
        #expect(store.tabs[0].id == tab1.id)
        #expect(store.tabs[1].id == tab2.id)
        #expect(store.tabs[0].position == 0)
        #expect(store.tabs[1].position == 1)
    }

    @Test func firstAppendedTabBecomesActive() {
        let store = TabStore()
        let tab = Tab(name: "first")
        store.append(tab: tab)
        #expect(store.activeTabID == tab.id)
    }

    @Test func subsequentAppendDoesNotChangeActive() {
        let store = TabStore()
        let tab1 = Tab(name: "first")
        let tab2 = Tab(name: "second")
        store.append(tab: tab1)
        store.append(tab: tab2)
        #expect(store.activeTabID == tab1.id)
    }

    @Test func closeRemovesAndReindexes() {
        let store = TabStore()
        let tabA = Tab(name: "a")
        let tabB = Tab(name: "b")
        let tabC = Tab(name: "c")
        store.append(tab: tabA)
        store.append(tab: tabB)
        store.append(tab: tabC)

        store.close(id: tabB.id)

        #expect(store.tabs.count == 2)
        #expect(store.tabs[0].id == tabA.id)
        #expect(store.tabs[0].position == 0)
        #expect(store.tabs[1].id == tabC.id)
        #expect(store.tabs[1].position == 1)
    }

    @Test func closeActiveTabSwitchesToPrevious() {
        let store = TabStore()
        let tabA = Tab(name: "a")
        let tabB = Tab(name: "b")
        let tabC = Tab(name: "c")
        store.append(tab: tabA)
        store.append(tab: tabB)
        store.append(tab: tabC)
        store.activeTabID = tabC.id

        store.close(id: tabC.id)

        #expect(store.activeTabID == tabB.id)
    }

    @Test func closeFirstActiveTabSwitchesToNext() {
        let store = TabStore()
        let tabA = Tab(name: "a")
        let tabB = Tab(name: "b")
        store.append(tab: tabA)
        store.append(tab: tabB)
        store.activeTabID = tabA.id

        store.close(id: tabA.id)

        #expect(store.activeTabID == tabB.id)
    }

    @Test func closeLastTabClearsActive() {
        let store = TabStore()
        let tab = Tab(name: "only")
        store.append(tab: tab)

        store.close(id: tab.id)

        #expect(store.activeTabID == nil)
        #expect(store.tabs.isEmpty)
    }

    @Test func moveReordersAndReindexes() {
        let store = TabStore()
        let tabA = Tab(name: "a")
        let tabB = Tab(name: "b")
        let tabC = Tab(name: "c")
        store.append(tab: tabA)
        store.append(tab: tabB)
        store.append(tab: tabC)

        store.move(fromIndex: 2, toIndex: 0)

        #expect(store.tabs.map(\.name) == ["c", "a", "b"])
        #expect(store.tabs.map(\.position) == [0, 1, 2])
    }

    @Test func moveToSameIndexIsNoop() {
        let store = TabStore()
        let tabA = Tab(name: "a")
        let tabB = Tab(name: "b")
        store.append(tab: tabA)
        store.append(tab: tabB)

        store.move(fromIndex: 0, toIndex: 0)

        #expect(store.tabs.map(\.name) == ["a", "b"])
    }

    @Test func renameUpdatesName() {
        let store = TabStore()
        let tab = Tab(name: "old")
        store.append(tab: tab)

        store.rename(id: tab.id, name: "new")

        #expect(tab.name == "new")
        #expect(tab.displayName == "new")
    }

    @Test func setColorUpdatesColor() {
        let store = TabStore()
        let tab = Tab()
        store.append(tab: tab)

        store.setColor(id: tab.id, color: .preset(.red))

        #expect(tab.color == .preset(.red))
    }

    @Test func tabAtIndexReturnsCorrectTab() {
        let store = TabStore()
        let tabA = Tab(name: "a")
        let tabB = Tab(name: "b")
        store.append(tab: tabA)
        store.append(tab: tabB)

        #expect(store.tab(at: 0)?.id == tabA.id)
        #expect(store.tab(at: 1)?.id == tabB.id)
        #expect(store.tab(at: 2) == nil)
        #expect(store.tab(at: -1) == nil)
    }

    @Test func tabForSurfaceIDFindsTab() {
        let store = TabStore()
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        store.append(tab: tab)

        #expect(store.tab(forSurfaceID: surfaceID)?.id == tab.id)
        #expect(store.tab(forSurfaceID: UUID()) == nil)
    }

    @Test func activeTabReturnsCorrectTab() {
        let store = TabStore()
        let tabA = Tab(name: "a")
        let tabB = Tab(name: "b")
        store.append(tab: tabA)
        store.append(tab: tabB)
        store.activeTabID = tabB.id

        #expect(store.activeTab?.id == tabB.id)
    }

    @Test func positionInvariantHoldsAfterMutations() {
        let store = TabStore()
        for idx in 0..<5 {
            store.append(tab: Tab(name: "tab-\(idx)"))
        }

        // Close middle
        store.close(id: store.tabs[2].id)
        for (idx, tab) in store.tabs.enumerated() {
            #expect(tab.position == idx)
        }

        // Move
        store.move(fromIndex: 0, toIndex: 2)
        for (idx, tab) in store.tabs.enumerated() {
            #expect(tab.position == idx)
        }

        // Close first
        store.close(id: store.tabs[0].id)
        for (idx, tab) in store.tabs.enumerated() {
            #expect(tab.position == idx)
        }
    }
}
