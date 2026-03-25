import Foundation

struct SessionSnapshot: Codable {
    static let currentVersion = 2

    var version: Int = Self.currentVersion
    var windowX: Double = 0
    var windowY: Double = 0
    var windowWidth: Double = 0
    var windowHeight: Double = 0
    var sidebarWidth: Double = 200
    var surfaceTintEnabled: Bool = true
    var activeTabID: UUID?
    var tabs: [TabSnapshot]
    var repoColorOverrides: [String: TabColor] = [:]

    init(
        windowX: Double = 0, windowY: Double = 0,
        windowWidth: Double = 0, windowHeight: Double = 0,
        sidebarWidth: Double = 200,
        surfaceTintEnabled: Bool = true,
        activeTabID: UUID? = nil,
        tabs: [TabSnapshot] = [],
        repoColorOverrides: [String: TabColor] = [:]
    ) {
        self.windowX = windowX
        self.windowY = windowY
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.sidebarWidth = sidebarWidth
        self.surfaceTintEnabled = surfaceTintEnabled
        self.activeTabID = activeTabID
        self.tabs = tabs
        self.repoColorOverrides = repoColorOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        windowX = try container.decode(Double.self, forKey: .windowX)
        windowY = try container.decode(Double.self, forKey: .windowY)
        windowWidth = try container.decode(Double.self, forKey: .windowWidth)
        windowHeight = try container.decode(Double.self, forKey: .windowHeight)
        sidebarWidth = try container.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? 200
        surfaceTintEnabled = try container.decodeIfPresent(Bool.self, forKey: .surfaceTintEnabled) ?? true
        activeTabID = try container.decodeIfPresent(UUID.self, forKey: .activeTabID)
        tabs = try container.decode([TabSnapshot].self, forKey: .tabs)
        repoColorOverrides = try container.decodeIfPresent(
            [String: TabColor].self, forKey: .repoColorOverrides
        ) ?? [:]
    }
}

struct TabSnapshot: Codable {
    var tabID: UUID
    var name: String
    var position: Int
    var focusedLeafID: UUID?
    var splitLayout: SplitNode
    /// Working directory per leaf, keyed by leaf ID.
    var leafDirectories: [UUID: String]
}
