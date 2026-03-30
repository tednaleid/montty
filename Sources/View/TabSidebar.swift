import SwiftUI

struct TabSidebar: View {
    @Bindable var tabStore: TabStore
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onSetRepoColor: (String, TabColor?) -> Void
    let onSetTabColor: (Tab, TabColor?) -> Void
    var repoColorOverrides: [String: TabColor] = [:]
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
                                guard let draggedIDString = items.first,
                                      let draggedID = UUID(uuidString: draggedIDString),
                                      let fromIndex = tabStore.tabs.firstIndex(
                                          where: { $0.id == draggedID }),
                                      let toIndex = tabStore.tabs.firstIndex(
                                          where: { $0.id == tab.id }),
                                      fromIndex != toIndex
                                else { return false }
                                tabStore.move(fromIndex: fromIndex, toIndex: toIndex)
                                return true
                            }
                            .contextMenu {
                                TabContextMenu(
                                    tab: tab,
                                    repoColorOverrides: repoColorOverrides,
                                    onRename: {
                                        editingTabID = tab.id
                                    },
                                    onSetRepoColor: onSetRepoColor,
                                    onSetTabColor: { color in
                                        onSetTabColor(tab, color)
                                    },
                                    onClose: {
                                        onCloseTab(tab.id)
                                    }
                                )
                            }
                        }
                    }
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
}
