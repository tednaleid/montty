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
                onSetColor: { tabStore.setColor(id: $0, color: $1) }
            )
            .frame(minWidth: 150, idealWidth: sidebarWidth, maxWidth: 300)

            // Terminal content for the active tab
            terminalContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
        if let activeTab = tabStore.activeTab,
           let surfaceView = appDelegate.surfaceView(for: activeTab.surfaceID) {
            Ghostty.SurfaceWrapper(surfaceView: surfaceView)
                .id(activeTab.surfaceID)
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }
}
