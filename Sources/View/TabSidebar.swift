import SwiftUI

struct TabSidebar: View {
    @Bindable var tabStore: TabStore
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onSetColor: (UUID, TabColor) -> Void

    @State private var editingTabID: UUID?
    @State private var draggedTabID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $tabStore.activeTabID) {
                ForEach(tabStore.tabs) { tab in
                    TabRow(
                        tab: tab,
                        isActive: tab.id == tabStore.activeTabID,
                        editingTabID: $editingTabID
                    )
                    .tag(tab.id)
                    .draggable(tab.id.uuidString) {
                        // Drag preview
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
