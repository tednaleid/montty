import Foundation

struct SessionSnapshot: Codable {
    static let currentVersion = 1

    var version: Int = Self.currentVersion
    var windowX: Double = 0
    var windowY: Double = 0
    var windowWidth: Double = 0
    var windowHeight: Double = 0
    var sidebarWidth: Double = 200
    var activeTabID: UUID?
    var tabs: [TabSnapshot]

    init(
        windowX: Double = 0, windowY: Double = 0,
        windowWidth: Double = 0, windowHeight: Double = 0,
        sidebarWidth: Double = 200,
        activeTabID: UUID? = nil,
        tabs: [TabSnapshot] = []
    ) {
        self.windowX = windowX
        self.windowY = windowY
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.sidebarWidth = sidebarWidth
        self.activeTabID = activeTabID
        self.tabs = tabs
    }
}

struct TabSnapshot: Codable {
    var tabID: UUID
    var name: String
    var color: TabColor
    var position: Int
    var focusedLeafID: UUID?
    var splitLayout: SplitNode
    /// Working directory per leaf, keyed by leaf ID.
    var leafDirectories: [UUID: String]
}
