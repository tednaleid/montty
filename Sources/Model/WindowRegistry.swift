// ABOUTME: Every open window in order, and the lookups that answer which window
// ABOUTME: owns a given surface or tab.

import Foundation

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

    /// A surface belongs to exactly one tab in exactly one window. Callers that
    /// hold only a `MONTTY_SURFACE_ID` use this to find both.
    func locate(surfaceID: UUID) -> (window: WindowModel, tab: Tab)? {
        for window in windows {
            if let tab = window.tabStore.tab(forSurfaceID: surfaceID) {
                return (window, tab)
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
