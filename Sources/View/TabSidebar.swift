// ABOUTME: The window's vertical sidebar: a scrolling list of tab rows and a new-tab button.
// ABOUTME: Handles row selection, renaming, reordering, moving tabs between windows, and jump labels.
import SwiftUI

struct TabSidebar: View {
    @Bindable var tabStore: TabStore
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void
    /// A dragged tab was dropped at this index of this window. The tab may
    /// belong to another window. Returns whether the drop was accepted.
    let onMoveTab: (UUID, Int) -> Bool
    let onControl: (Tab, ControlCommand) -> Void
    var repoColorOverrides: [String: PaneTint] = [:]
    var shared = SharedSettings()
    var jumpLabels: [UUID: String] = [:]
    var onJumpToSurface: ((UUID, UUID) -> Void)?

    @State private var editingTabID: UUID?

    var body: some View {
        VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tabStore.tabs) { tab in
                            let isActive = tab.id == tabStore.activeTabID
                            TabRow(
                                tab: tab,
                                isActive: isActive,
                                repoColorOverrides: repoColorOverrides,
                                editingTabID: $editingTabID,
                                showsMinimap: tab.showsMinimap(
                                    global: shared.app.minimapVisibility),
                                minimapHeight: tab.minimapHeight ?? shared.app.minimapHeight,
                                tabTintStrength: tab.tabTintStrength(shared: shared),
                                jumpLabels: jumpLabels,
                                onPaneTap: { leafID in
                                    onJumpToSurface?(tab.id, leafID)
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                tabStore.activeTabID = tab.id
                            }
                            .draggable(tab.id.uuidString) {
                                Text(tab.tabInfo.displayName)
                                    .padding(4)
                            }
                            .dropDestination(for: String.self) { items, _ in
                                guard let toIndex = tabStore.tabs.firstIndex(
                                    where: { $0.id == tab.id })
                                else { return false }
                                return drop(items, at: toIndex)
                            }
                            .contextMenu {
                                TabContextMenu(
                                    tab: tab,
                                    repoColorOverrides: repoColorOverrides,
                                    onRename: {
                                        editingTabID = tab.id
                                    },
                                    onControl: { command in
                                        onControl(tab, command)
                                    },
                                    onClose: {
                                        onCloseTab(tab.id)
                                    }
                                )
                            }
                        }
                    }
                }
                // Below the last row: append, which is how a tab from another
                // window lands at the end.
                .dropDestination(for: String.self) { items, _ in
                    drop(items, at: tabStore.tabs.count)
                }

                Divider()

                Button(action: onNewTab) {
                    HStack {
                        Image(systemName: "plus")
                        Text("New Tab")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
    }

    /// The dragged tab's id is the payload; anything else dropped here (text
    /// from another app) is refused rather than guessed at.
    private func drop(_ items: [String], at index: Int) -> Bool {
        guard let draggedID = items.first.flatMap(UUID.init(uuidString:)) else { return false }
        return onMoveTab(draggedID, index)
    }
}
