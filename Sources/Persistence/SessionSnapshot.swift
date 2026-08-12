// ABOUTME: The saved shape of a session: app-wide settings plus one entry per
// ABOUTME: window, decoded from both that shape and the flat single-window one.

import Foundation

struct SessionSnapshot: Codable {
    static let currentVersion = 4

    var version: Int = Self.currentVersion
    var surfaceTintEnabled: Bool = true
    var windows: [WindowSnapshot] = []
    var keyWindowID: UUID?
    var repoColorOverrides: [String: PaneTint] = [:]

    init(
        surfaceTintEnabled: Bool = true,
        windows: [WindowSnapshot] = [],
        keyWindowID: UUID? = nil,
        repoColorOverrides: [String: PaneTint] = [:]
    ) {
        self.surfaceTintEnabled = surfaceTintEnabled
        self.windows = windows
        self.keyWindowID = keyWindowID
        self.repoColorOverrides = repoColorOverrides
    }

    /// Reads both shapes. A file with a `windows` array is version 4. A file
    /// without one carries a single window in flat top-level keys, and becomes
    /// one window here. Every key at the `SessionSnapshot` and `WindowSnapshot`
    /// level is optional, so a file whose shape has moved on at those levels
    /// decodes to an empty session rather than throwing, which would send it to
    /// quarantine as though it were corrupt. Tabs are decoded by `TabSnapshot`,
    /// which still requires its own fields, so a shape change within a tab can
    /// still throw.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
            ?? Self.currentVersion
        surfaceTintEnabled = try container.decodeIfPresent(
            Bool.self, forKey: .surfaceTintEnabled) ?? true
        repoColorOverrides = try container.decodeIfPresent(
            [String: PaneTint].self, forKey: .repoColorOverrides) ?? [:]

        if let windows = try container.decodeIfPresent(
            [WindowSnapshot].self, forKey: .windows
        ) {
            self.windows = windows
            keyWindowID = try container.decodeIfPresent(UUID.self, forKey: .keyWindowID)
            return
        }

        let legacy = try LegacyWindow(from: decoder)
        windows = legacy.tabs.isEmpty ? [] : [legacy.asWindowSnapshot()]
        keyWindowID = windows.first?.windowID
    }
}

struct WindowSnapshot: Codable {
    var windowID: UUID
    var frame: WindowFrame
    var sidebarWidth: Double
    var activeTabID: UUID?
    var tabs: [TabSnapshot]
}

extension WindowSnapshot {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowID = try container.decodeIfPresent(UUID.self, forKey: .windowID) ?? UUID()
        frame = try container.decodeIfPresent(WindowFrame.self, forKey: .frame)
            ?? WindowFrame(x: 0, y: 0, width: 0, height: 0)
        sidebarWidth = try container.decodeIfPresent(
            Double.self, forKey: .sidebarWidth) ?? 200
        activeTabID = try container.decodeIfPresent(UUID.self, forKey: .activeTabID)
        tabs = try container.decodeIfPresent([TabSnapshot].self, forKey: .tabs) ?? []
    }
}

/// The single window a session before version 4 stored in flat top-level keys.
private struct LegacyWindow: Decodable {
    var windowX: Double = 0
    var windowY: Double = 0
    var windowWidth: Double = 0
    var windowHeight: Double = 0
    var sidebarWidth: Double = 200
    var activeTabID: UUID?
    var tabs: [TabSnapshot] = []

    /// `LegacyWindow` conforms only to `Decodable`, so nothing else triggers
    /// synthesis of `CodingKeys` -- it is spelled out here instead.
    private enum CodingKeys: String, CodingKey {
        case windowX, windowY, windowWidth, windowHeight, sidebarWidth, activeTabID, tabs
    }

    func asWindowSnapshot() -> WindowSnapshot {
        WindowSnapshot(
            windowID: UUID(),
            frame: WindowFrame(
                x: windowX, y: windowY, width: windowWidth, height: windowHeight),
            sidebarWidth: sidebarWidth,
            activeTabID: activeTabID,
            tabs: tabs
        )
    }
}

extension LegacyWindow {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowX = try container.decodeIfPresent(Double.self, forKey: .windowX) ?? 0
        windowY = try container.decodeIfPresent(Double.self, forKey: .windowY) ?? 0
        windowWidth = try container.decodeIfPresent(Double.self, forKey: .windowWidth) ?? 0
        windowHeight = try container.decodeIfPresent(Double.self, forKey: .windowHeight) ?? 0
        sidebarWidth = try container.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? 200
        activeTabID = try container.decodeIfPresent(UUID.self, forKey: .activeTabID)
        tabs = try container.decodeIfPresent([TabSnapshot].self, forKey: .tabs) ?? []
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
    /// Per-surface color override, keyed by leaf ID. Surfaces get fresh IDs on
    /// restore; leaf IDs survive, which is what makes this stick.
    var leafColorOverrides: [UUID: PaneTint] = [:]
    /// Tab-level color override, if set.
    var colorOverride: PaneTint?
}

extension TabSnapshot {
    /// The synthesized decoder would require every key, including
    /// `leafColorOverrides`, because Swift's `Decodable` synthesis ignores a
    /// property's default value and always emits `decode` instead of
    /// `decodeIfPresent`. A hand-written decoder is required so a session
    /// written before this field existed still loads. Kept in an extension so
    /// the memberwise initializer stays available for callers and tests.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabID = try container.decode(UUID.self, forKey: .tabID)
        name = try container.decode(String.self, forKey: .name)
        position = try container.decode(Int.self, forKey: .position)
        focusedLeafID = try container.decodeIfPresent(UUID.self, forKey: .focusedLeafID)
        splitLayout = try container.decode(SplitNode.self, forKey: .splitLayout)
        leafDirectories = try container.decode([UUID: String].self, forKey: .leafDirectories)
        leafColorOverrides = try container.decodeIfPresent(
            [UUID: PaneTint].self, forKey: .leafColorOverrides
        ) ?? [:]
        colorOverride = try container.decodeIfPresent(PaneTint.self, forKey: .colorOverride)
    }
}
