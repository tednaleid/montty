import SwiftUI

struct TabSidebar: View {
    @Bindable var tabStore: TabStore
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onSetColor: (UUID, TabColor) -> Void

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $tabStore.activeTabID) {
                ForEach(tabStore.tabs) { tab in
                    TabRow(tab: tab, isActive: tab.id == tabStore.activeTabID)
                        .tag(tab.id)
                        .contextMenu {
                            TabContextMenu(
                                tab: tab,
                                onRename: {
                                    // Double-click on TabRow handles inline rename
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
