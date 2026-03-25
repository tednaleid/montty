import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var ghostty: Ghostty.App
    @EnvironmentObject var appDelegate: AppDelegate
    var tabStore: TabStore

    @State private var dragStartWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            if appDelegate.sidebarVisible {
                TabSidebar(
                    tabStore: tabStore,
                    onNewTab: { appDelegate.createTab() },
                    onCloseTab: { appDelegate.closeTab(id: $0) },
                    onSetRepoColor: { identity, color in
                        if let color {
                            appDelegate.repoColorOverrides[identity] = color
                        } else {
                            appDelegate.repoColorOverrides.removeValue(forKey: identity)
                        }
                    },
                    repoColorOverrides: appDelegate.repoColorOverrides,
                    jumpLabels: appDelegate.jumpState?.leafToLabel ?? [:],
                    onJumpToSurface: { tabID, leafID in
                        appDelegate.exitJumpMode()
                        appDelegate.jumpToSurface(tabID: tabID, leafID: leafID)
                    }
                )
                .frame(width: appDelegate.sidebarWidth)

                // Draggable divider between sidebar and terminal
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                    .contentShape(Rectangle().inset(by: -3))
                    .cursor(.resizeLeftRight)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if dragStartWidth == 0 {
                                    dragStartWidth = appDelegate.sidebarWidth
                                }
                                let newWidth = dragStartWidth + value.translation.width
                                appDelegate.sidebarWidth = min(max(newWidth, 150), 400)
                            }
                            .onEnded { _ in
                                dragStartWidth = 0
                            }
                    )
            }

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
            updateWindowTitle(tab: tab)
        }
        .onAppear {
            if let tab = tabStore.activeTab {
                updateWindowTitle(tab: tab)
            }
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
        if let activeTab = tabStore.activeTab {
            SplitContainerView(
                node: activeTab.splitRoot,
                focusedLeafID: activeTab.focusedLeafID,
                surfaceLookup: { appDelegate.surfaceView(for: $0) },
                jumpLabels: appDelegate.jumpState?.leafToLabel ?? [:],
                surfaceDirectories: activeTab.surfaceDirectories,
                repoColorOverrides: appDelegate.repoColorOverrides,
                surfaceTintEnabled: appDelegate.surfaceTintEnabled
            )
            .id(activeTab.id)
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }

    private func updateWindowTitle(tab: Tab) {
        DispatchQueue.main.async {
            NSApp.mainWindow?.title = "Montty - \(tab.tabInfo.displayName)"
        }
    }
}
