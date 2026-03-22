import SwiftUI

struct TabSidebar: View {
    @Bindable var tabStore: TabStore
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onSetColor: (UUID, TabColor) -> Void

    @State private var editingTabID: UUID?
    @State private var draggedTabID: UUID?

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
                            editingTabID: $editingTabID
                        )
                        .tag(tab.id)
                        .listRowInsets(EdgeInsets())
                        .draggable(tab.id.uuidString) {
                            Text(tab.tabInfo.displayName)
                                .padding(4)
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
                    .onMove { source, destination in
                        guard let fromIndex = source.first else { return }
                        let toIndex = destination > fromIndex
                            ? destination - 1 : destination
                        tabStore.move(fromIndex: fromIndex, toIndex: toIndex)
                    }
                }
                .listStyle(.sidebar)

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
