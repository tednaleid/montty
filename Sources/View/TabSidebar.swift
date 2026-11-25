// ABOUTME: The window's vertical sidebar: a scrolling list of tab rows and a new-tab button.
// ABOUTME: Handles selection, renaming, jump labels, and dragging tabs within and between windows.
import SwiftUI

struct TabSidebar: View {
    @Bindable var tabStore: TabStore
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void
    /// A dragged tab was dropped to land at this index of this window. The tab
    /// may belong to another window. Returns whether the move happened.
    let onMoveTab: (UUID, Int) -> Bool
    /// A drag of this tab began, in this window or another.
    let onDragTab: (UUID) -> Void
    /// The drag of this tab ended at this point in screen coordinates, or was
    /// cancelled when the point is nil.
    let onDragTabEnded: (UUID, CGPoint?) -> Void
    /// Asks for this tab to move into a window of its own.
    let onMoveTabToNewWindow: (UUID) -> Void
    /// The tab most recently dragged, which a window other than its own cannot
    /// otherwise learn while the drag is still over it.
    let draggingTabID: () -> UUID?
    let onControl: (Tab, ControlCommand) -> Void
    var repoColorOverrides: [String: PaneTint] = [:]
    var shared = SharedSettings()
    var jumpLabels: [UUID: String] = [:]
    var onJumpToSurface: ((UUID, UUID) -> Void)?

    @State private var editingTabID: UUID?
    @State private var dropIndicator: DropIndicator?
    @State private var rowHeights: [UUID: CGFloat] = [:]

    /// The gap a drag is over and the part of the sidebar reporting it. Gaps
    /// are reported by whichever target the cursor is in, and the one it just
    /// left may report leaving after the one it entered reports arriving, so a
    /// target only ever clears its own.
    private struct DropIndicator {
        let owner: String
        let gap: Int
    }

    private static let listOwner = "list"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tabStore.tabs.enumerated()), id: \.element.id) { index, tab in
                        tabRow(tab, at: index)
                    }
                }
                // Tabs slide to their new places when one is dropped, rather
                // than snapping.
                .animation(.easeInOut(duration: 0.2), value: tabStore.tabs.map(\.id))
            }
            // Below the last row: the end of the list, which is how a tab from
            // another window lands last.
            .onDrop(of: [.monttyTab], delegate: dropDelegate(
                owner: Self.listOwner,
                gapAt: { _ in tabStore.tabs.count }
            ))

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

    private func tabRow(_ tab: Tab, at index: Int) -> some View {
        TabRow(
            tab: tab,
            isActive: tab.id == tabStore.activeTabID,
            repoColorOverrides: repoColorOverrides,
            editingTabID: $editingTabID,
            showsMinimap: tab.showsMinimap(global: shared.app.minimapVisibility),
            minimapHeight: tab.minimapHeight ?? shared.app.minimapHeight,
            tabTintStrength: tab.tabTintStrength(shared: shared),
            jumpLabels: jumpLabels,
            onPaneTap: { leafID in
                onJumpToSurface?(tab.id, leafID)
            }
        )
        // Shifted inside the drop target, which stays where it was: moving the
        // target itself would carry the row out from under the cursor and
        // change the gap it reports.
        .offset(y: gapShift(forRowAt: index))
        .animation(.easeOut(duration: 0.12), value: insertionGap)
        .contentShape(Rectangle())
        .onTapGesture {
            tabStore.activeTabID = tab.id
        }
        .background(TabDragSource(
            tabID: tab.id,
            title: tab.tabInfo.displayName,
            onBegin: onDragTab,
            onEnd: onDragTabEnded
        ))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            rowHeights[tab.id] = height
        }
        .onDrop(of: [.monttyTab], delegate: dropDelegate(
            owner: tab.id.uuidString,
            gapAt: { point in
                TabDropTarget.gap(
                    overRow: index,
                    lowerHalf: point.y > (rowHeights[tab.id] ?? 0) / 2
                )
            }
        ))
        .overlay(alignment: .top) {
            if insertionGap == index { InsertionLine() }
        }
        .overlay(alignment: .bottom) {
            if index == tabStore.tabs.count - 1, insertionGap == tabStore.tabs.count {
                InsertionLine()
            }
        }
        .contextMenu { contextMenu(for: tab) }
    }

    private func contextMenu(for tab: Tab) -> some View {
        TabContextMenu(
            tab: tab,
            repoColorOverrides: repoColorOverrides,
            onRename: {
                editingTabID = tab.id
            },
            onControl: { command in
                onControl(tab, command)
            },
            // A window's only tab has no other window to leave behind.
            onMoveToNewWindow: tabStore.tabs.count > 1
                ? { onMoveTabToNewWindow(tab.id) } : nil,
            onClose: {
                onCloseTab(tab.id)
            }
        )
    }

    /// How far a row moves to open room for the insertion line: rows above the
    /// gap up, rows below it down, so the space opens around the line.
    private func gapShift(forRowAt index: Int) -> CGFloat {
        guard let gap = insertionGap else { return 0 }
        return index < gap ? -Self.gapSpread : Self.gapSpread
    }

    private static let gapSpread: CGFloat = 4

    /// The gap to draw the line in: the one a drag is over, unless dropping
    /// there would leave the dragged tab where it is.
    private var insertionGap: Int? {
        guard let gap = dropIndicator?.gap else { return nil }
        let draggedIndex = draggingTabID().flatMap { id in
            tabStore.tabs.firstIndex { $0.id == id }
        }
        return TabDropTarget.landingIndex(gap: gap, draggedIndex: draggedIndex) == nil ? nil : gap
    }

    private func dropDelegate(
        owner: String,
        gapAt: @escaping (CGPoint) -> Int
    ) -> TabDropDelegate {
        TabDropDelegate(
            gapAt: gapAt,
            onTarget: { gap in
                if let gap {
                    dropIndicator = DropIndicator(owner: owner, gap: gap)
                } else if dropIndicator?.owner == owner {
                    dropIndicator = nil
                }
            },
            onDrop: { provider, gap in
                moveDroppedTab(from: provider, intoGap: gap)
            }
        )
    }

    /// The dragged tab's id is the payload; a provider that carries none names
    /// no tab and is ignored.
    private func moveDroppedTab(from provider: NSItemProvider, intoGap gap: Int) {
        TabDragPayload.tabID(from: provider) { id in
            guard let id else { return }
            let draggedIndex = tabStore.tabs.firstIndex { $0.id == id }
            guard let landing = TabDropTarget.landingIndex(
                gap: gap, draggedIndex: draggedIndex
            ) else { return }
            _ = onMoveTab(id, landing)
        }
    }
}

/// The line drawn between two rows where a dragged tab will land.
private struct InsertionLine: View {
    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(height: 2)
            .allowsHitTesting(false)
    }
}
