import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var ghostty: Ghostty.App
    @EnvironmentObject var appDelegate: AppDelegate
    var tabStore: TabStore

    private let sidebarWidth: CGFloat = 200

    var body: some View {
        HSplitView {
            TabSidebar(
                tabStore: tabStore,
                onNewTab: { appDelegate.createTab() },
                onCloseTab: { appDelegate.closeTab(id: $0) },
                onSetColor: { tabStore.setColor(id: $0, color: $1) },
                jumpLabels: appDelegate.jumpState?.leafToLabel ?? [:],
                onJumpToSurface: { tabID, leafID in
                    appDelegate.exitJumpMode()
                    appDelegate.jumpToSurface(tabID: tabID, leafID: leafID)
                }
            )
            .frame(minWidth: 150, idealWidth: sidebarWidth, maxWidth: 300)

            // Terminal content for the active tab
            terminalContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: tabStore.activeTabID) { _, newID in
            guard let newID = newID,
                  let tab = tabStore.tabs.first(where: { $0.id == newID }),
                  let surfaceID = tab.focusedSurfaceID,
                  let surfaceView = appDelegate.surfaceView(for: surfaceID) else { return }
            Ghostty.moveFocus(to: surfaceView)
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
        if let activeTab = tabStore.activeTab {
            SplitContainerView(
                node: activeTab.splitRoot,
                focusedLeafID: activeTab.focusedLeafID,
                tabColor: activeTab.color,
                surfaceLookup: { appDelegate.surfaceView(for: $0) },
                onFocusLeaf: { leafID in
                    appDelegate.setFocusedLeaf(leafID, in: activeTab)
                },
                jumpLabels: appDelegate.jumpState?.leafToLabel ?? [:],
                surfaceDirectories: activeTab.surfaceDirectories
            )
            .id(activeTab.id)
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }
}
