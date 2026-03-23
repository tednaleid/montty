import SwiftUI

struct TabSidebar: View {
    @Bindable var tabStore: TabStore
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onSetColor: (UUID, TabColor) -> Void
    var jumpLabels: [UUID: String] = [:]
    var onJumpToSurface: ((UUID, UUID) -> Void)?

    @State private var editingTabID: UUID?

    private var activeTabColor: Color {
        guard let tab = tabStore.activeTab else { return .accentColor }
        switch tab.color {
        case .preset(let preset): return preset.swiftUIColor
        case .auto: return .accentColor
        }
    }

    var body: some View {
        VStack(spacing: 0) {
                List(selection: $tabStore.activeTabID) {
                    ForEach(tabStore.tabs) { tab in
                        let isActive = tab.id == tabStore.activeTabID
                        TabRow(
                            tab: tab,
                            isActive: isActive,
                            activeTabColor: activeTabColor,
                            editingTabID: $editingTabID,
                            jumpLabels: jumpLabels,
                            onPaneTap: { leafID in
                                onJumpToSurface?(tab.id, leafID)
                            }
                        )
                        .tag(tab.id)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
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
                                onRename: {
                                    editingTabID = tab.id
                                },
                                onSetColor: { color in
                                    onSetColor(tab.id, color)
                                },
                                onClose: {
                                    onCloseTab(tab.id)
                                }
                            )
                        }
                    }
                }
                .listStyle(.plain)

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
