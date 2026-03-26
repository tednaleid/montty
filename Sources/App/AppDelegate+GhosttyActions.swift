import Foundation
import GhosttyKit

// MARK: - Ghostty action routing

extension AppDelegate {
    func observeGhosttyActions() {
        let center = NotificationCenter.default
        observeTabActions(center)
        observeSplitActions(center)
        observeSurfaceFocus(center)
    }

    private func observeTabActions(_ center: NotificationCenter) {
        center.addObserver(
            forName: Ghostty.Notification.ghosttyNewTab,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.createTab()
        }

        center.addObserver(
            forName: .ghosttyCloseTab,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let surfaceView = notification.object as? Ghostty.SurfaceView,
                  let tab = self.tabStore.tab(forSurfaceID: surfaceView.id) else { return }
            self.closeTab(id: tab.id)
        }

        center.addObserver(
            forName: Ghostty.Notification.ghosttyCloseSurface,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let surfaceView = notification.object as? Ghostty.SurfaceView else { return }
            self.closeSurface(surfaceID: surfaceView.id)
        }

        center.addObserver(
            forName: Ghostty.Notification.ghosttyGotoTab,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let tabIndex = notification.userInfo?[
                      Ghostty.Notification.GotoTabKey
                  ] as? ghostty_action_goto_tab_e else { return }
            self.handleGotoTab(tabIndex)
        }
    }

    private func handleGotoTab(_ tabIndex: ghostty_action_goto_tab_e) {
        let tabs = tabStore.tabs
        guard !tabs.isEmpty else { return }

        let rawValue = tabIndex.rawValue
        switch rawValue {
        case GHOSTTY_GOTO_TAB_PREVIOUS.rawValue:
            // Previous tab
            if let activeID = tabStore.activeTabID,
               let currentIndex = tabs.firstIndex(where: { $0.id == activeID }),
               currentIndex > 0 {
                tabStore.activeTabID = tabs[currentIndex - 1].id
            }

        case GHOSTTY_GOTO_TAB_NEXT.rawValue:
            // Next tab
            if let activeID = tabStore.activeTabID,
               let currentIndex = tabs.firstIndex(where: { $0.id == activeID }),
               currentIndex < tabs.count - 1 {
                tabStore.activeTabID = tabs[currentIndex + 1].id
            }

        case GHOSTTY_GOTO_TAB_LAST.rawValue:
            // Last tab
            tabStore.activeTabID = tabs.last?.id

        default:
            // Positive values are 1-based tab indices
            let index = Int(rawValue) - 1
            if let tab = tabStore.tab(at: index) {
                tabStore.activeTabID = tab.id
            }
        }
    }

    private func observeSurfaceFocus(_ center: NotificationCenter) {
        center.addObserver(
            forName: Ghostty.Notification.ghosttySurfaceFocused,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let surfaceView = notification.object as? Ghostty.SurfaceView,
                  let tab = self.tabStore.tab(forSurfaceID: surfaceView.id),
                  let leaf = SplitTree.findLeaf(
                      node: tab.splitRoot, surfaceID: surfaceView.id),
                  tab.focusedLeafID != leaf.id
            else { return }
            tab.focusedLeafID = leaf.id
            self.updateSurfaceFocus(for: tab)
        }
    }

    private func observeSplitActions(_ center: NotificationCenter) {
        center.addObserver(
            forName: Ghostty.Notification.ghosttyNewSplit,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let ghosttyDirection = notification.userInfo?["direction"]
                as? ghostty_action_split_direction_e
            let splitDirection: SplitDirection
            switch ghosttyDirection {
            case GHOSTTY_SPLIT_DIRECTION_LEFT: splitDirection = .left
            case GHOSTTY_SPLIT_DIRECTION_UP: splitDirection = .up
            case GHOSTTY_SPLIT_DIRECTION_DOWN: splitDirection = .down
            default: splitDirection = .right
            }
            self.splitSurface(direction: splitDirection)
        }

        center.addObserver(
            forName: Ghostty.Notification.ghosttyFocusSplit,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let tab = self.tabStore.activeTab,
                  let focusedLeafID = tab.focusedLeafID else { return }
            let direction = notification.userInfo?[
                Ghostty.Notification.SplitDirectionKey
            ] as? Ghostty.SplitFocusDirection

            if let target = focusTarget(
                root: tab.splitRoot, leafID: focusedLeafID,
                direction: direction
            ) {
                self.setFocusedLeaf(target.id, in: tab)
            }
        }

        center.addObserver(
            forName: Ghostty.Notification.didResizeSplit,
            object: nil, queue: .main
        ) { [weak self] notification in
            self?.handleResizeSplit(notification)
        }

        center.addObserver(
            forName: Ghostty.Notification.didEqualizeSplits,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let surfaceView = notification.object as? Ghostty.SurfaceView,
                  let tab = self.tabStore.tab(forSurfaceID: surfaceView.id)
            else { return }
            tab.splitRoot = SplitTree.equalize(node: tab.splitRoot)
        }
    }

    private func handleResizeSplit(_ notification: Foundation.Notification) {
        guard let surfaceView = notification.object as? Ghostty.SurfaceView,
              let tab = tabStore.tab(forSurfaceID: surfaceView.id),
              let focusedLeafID = tab.focusedLeafID,
              let directionRaw = notification.userInfo?[
                  Ghostty.Notification.ResizeSplitDirectionKey
              ] as? ghostty_action_resize_split_direction_e,
              let amount = notification.userInfo?[
                  Ghostty.Notification.ResizeSplitAmountKey
              ] as? UInt16
        else { return }

        let direction: SplitDirection
        switch directionRaw {
        case GHOSTTY_RESIZE_SPLIT_LEFT: direction = .left
        case GHOSTTY_RESIZE_SPLIT_RIGHT: direction = .right
        case GHOSTTY_RESIZE_SPLIT_UP: direction = .up
        case GHOSTTY_RESIZE_SPLIT_DOWN: direction = .down
        default: return
        }

        // Convert pixel amount to a ratio delta (approximate)
        let ratioDelta = CGFloat(amount) / 1000.0
        if let updated = SplitTree.resizeLeaf(
            node: tab.splitRoot, leafID: focusedLeafID,
            direction: direction, amount: ratioDelta
        ) {
            tab.splitRoot = updated
        }
    }

    /// Find the target leaf for a split focus navigation.
    private func focusTarget(
        root: SplitNode, leafID: UUID,
        direction: Ghostty.SplitFocusDirection?
    ) -> SurfaceLeaf? {
        switch direction {
        case .previous:
            return SplitTree.previousLeaf(node: root, before: leafID)
        case .next:
            return SplitTree.nextLeaf(node: root, after: leafID)
        case .left:
            return SplitTree.findNeighbor(node: root, leafID: leafID, direction: .left)
        case .right:
            return SplitTree.findNeighbor(node: root, leafID: leafID, direction: .right)
        case .up:
            return SplitTree.findNeighbor(node: root, leafID: leafID, direction: .up)
        case .down:
            return SplitTree.findNeighbor(node: root, leafID: leafID, direction: .down)
        default:
            return SplitTree.nextLeaf(node: root, after: leafID)
        }
    }
}
