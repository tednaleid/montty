// ABOUTME: The ordered list of a window's tabs and which one is active. Appends, closes,
// ABOUTME: moves, detaches, inserts, and renames tabs while keeping positions contiguous.
import Foundation

@Observable
final class TabStore {
    private(set) var tabs: [Tab] = []
    var activeTabID: UUID?
    /// The directory the last tab to close was showing. A window that has lost
    /// every tab still has to say where it was, and by then the tab that knew
    /// is gone.
    private(set) var lastClosedDirectory: String?

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
        lastClosedDirectory = tabs[index].focusedDirectory ?? lastClosedDirectory
        detach(id: id)
    }

    /// Takes a tab out of this store and hands it back, for a caller that is
    /// moving it somewhere else. Unlike `close`, the tab is not going away, so
    /// the store keeps no record of its directory.
    @discardableResult
    func detach(id: UUID) -> Tab? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }

        // If detaching the active tab, switch to adjacent
        if activeTabID == id {
            if index > 0 {
                activeTabID = tabs[index - 1].id
            } else if tabs.count > 1 {
                activeTabID = tabs[index + 1].id
            } else {
                activeTabID = nil
            }
        }

        let tab = tabs.remove(at: index)
        reindex()
        return tab
    }

    /// Places a tab at `index`, clamped to the ends. The first tab into an
    /// empty store becomes active.
    func insert(tab: Tab, at index: Int) {
        tabs.insert(tab, at: min(max(index, 0), tabs.count))
        reindex()
        if activeTabID == nil {
            activeTabID = tab.id
        }
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
