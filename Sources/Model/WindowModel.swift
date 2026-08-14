// ABOUTME: One window's model state, holding the tabs it owns and the chrome
// ABOUTME: settings that belong to it rather than to the application.

import Foundation

@Observable
final class WindowModel: Identifiable {
    let id: UUID
    /// A window's tabs are its own, created with it.
    let tabStore = TabStore()
    /// Each window carries its own sidebar, so its width belongs here.
    var sidebarWidth: Double
    var frame: WindowFrame

    init(
        id: UUID = UUID(),
        sidebarWidth: Double = 200,
        frame: WindowFrame = WindowFrame(x: 0, y: 0, width: 0, height: 0)
    ) {
        self.id = id
        self.sidebarWidth = sidebarWidth
        self.frame = frame
    }

    /// The directory this window is showing: the one its active tab is in, or
    /// -- once its tabs are gone -- the one the last tab to close was in.
    var directory: String? {
        (tabStore.activeTab ?? tabStore.tabs.first)?.focusedDirectory
            ?? tabStore.lastClosedDirectory
    }
}
