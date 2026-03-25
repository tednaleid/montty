import Foundation

@Observable
final class TabStore {
    private(set) var tabs: [Tab] = []
    var activeTabID: UUID?

    var activeTab: Tab? {
        tabs.first { $0.id == activeTabID }
    }

    func tab(at index: Int) -> Tab? {
        guard index >= 0, index < tabs.count else { return nil }
        return tabs[index]
    }

    func tab(forSurfaceID surfaceID: UUID) -> Tab? {
        tabs.first { tab in
            SplitTree.findLeaf(node: tab.splitRoot, surfaceID: surfaceID) != nil
        }
    }

    // MARK: - Mutations

    func append(tab: Tab) {
        tab.position = tabs.count
        tabs.append(tab)
        if activeTabID == nil {
            activeTabID = tab.id
        }
    }

    func close(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        // If closing the active tab, switch to adjacent
        if activeTabID == id {
            if index > 0 {
                activeTabID = tabs[index - 1].id
            } else if tabs.count > 1 {
                activeTabID = tabs[index + 1].id
            } else {
                activeTabID = nil
            }
        }

        tabs.remove(at: index)
        reindex()
    }

    func move(fromIndex: Int, toIndex: Int) {
        guard fromIndex != toIndex,
              fromIndex >= 0, fromIndex < tabs.count,
              toIndex >= 0, toIndex < tabs.count else { return }

        let tab = tabs.remove(at: fromIndex)
        tabs.insert(tab, at: toIndex)
        reindex()
    }

    func rename(id: UUID, name: String) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.name = name
    }

    // MARK: - Position invariant

    private func reindex() {
        for (index, tab) in tabs.enumerated() {
            tab.position = index
        }
    }
}
