// ABOUTME: Every open window in order, and the lookups that answer which window
// ABOUTME: owns a given surface or tab.

import Foundation

/// Where one surface lives: the window and tab that own it, and the surface ID
/// its view is keyed by.
struct SurfaceLocation {
    let window: WindowModel
    let tab: Tab
    let surfaceID: UUID
}

@Observable
final class WindowRegistry {
    private(set) var windows: [WindowModel] = []

    /// The window holding focus. Subsystems that act on "the current window"
    /// read this rather than assuming there is only one.
    var keyWindowID: UUID?

    var keyWindow: WindowModel? {
        windows.first { $0.id == keyWindowID } ?? windows.first
    }

    @discardableResult
    func add(_ window: WindowModel = WindowModel()) -> WindowModel {
        windows.append(window)
        if keyWindowID == nil { keyWindowID = window.id }
        return window
    }

    func remove(id: UUID) {
        windows.removeAll { $0.id == id }
        guard keyWindowID == id else { return }
        keyWindowID = windows.first?.id
    }

    func window(id: UUID) -> WindowModel? {
        windows.first { $0.id == id }
    }

    /// A surface belongs to exactly one tab in exactly one window. Callers
    /// holding a surface ID use this to find both.
    func locate(surfaceID: UUID) -> SurfaceLocation? {
        for window in windows {
            if let tab = window.tabStore.tab(forSurfaceID: surfaceID) {
                return SurfaceLocation(window: window, tab: tab, surfaceID: surfaceID)
            }
        }
        return nil
    }

    /// A `MONTTY_SURFACE_ID` names one surface in one tab of one window. The
    /// hook socket and the montty CLI carry only that string, so this is how
    /// they reach the pane that sent them wherever it lives.
    func locate(monttyID: String) -> SurfaceLocation? {
        for window in windows {
            for tab in window.tabStore.tabs {
                if let surfaceID = tab.surfaceToMonttyID.first(
                    where: { $0.value == monttyID }
                )?.key {
                    return SurfaceLocation(window: window, tab: tab, surfaceID: surfaceID)
                }
            }
        }
        return nil
    }

    /// A tab belongs to exactly one window. Callers deciding whether closing
    /// a tab should also close its window use this rather than assuming it's
    /// whichever window currently holds focus.
    func locate(tabID: UUID) -> WindowModel? {
        windows.first { window in
            window.tabStore.tabs.contains { $0.id == tabID }
        }
    }
}
