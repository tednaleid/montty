import SwiftUI

struct TabRow: View {
    let tab: Tab
    let isActive: Bool
    var repoColorOverrides: [String: TabColor] = [:]
    @Binding var editingTabID: UUID?
    var jumpLabels: [UUID: String] = [:]
    var onPaneTap: ((UUID) -> Void)?

    @State private var editName = ""
    @FocusState private var textFieldFocused: Bool

    private var isEditing: Bool {
        editingTabID == tab.id
    }

    private var info: TabInfo {
        tab.tabInfo
    }

    var body: some View {
        HStack(spacing: 0) {
            // Color indicator bar
            Rectangle()
                .fill(colorBarColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 3) {
                // Tab name (editable on double-tap)
                if isEditing {
                    TextField("Tab name", text: $editName, onCommit: {
                        tab.name = editName
                        editingTabID = nil
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 21, weight: .bold))
                    .focused($textFieldFocused)
                    .onAppear {
                        editName = tab.name
                        // Delay focus slightly so the view is in the hierarchy
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            textFieldFocused = true
                        }
                    }
                    .onExitCommand { editingTabID = nil }
                } else {
                    Text(info.displayName)
                        .font(.system(size: 21, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .onTapGesture(count: 2) {
                            editingTabID = tab.id
                        }
                }

                // Git info line
                if let git = info.gitInfo {
                    HStack(spacing: 4) {
                        Text(git.repoName)
                            .foregroundStyle(.secondary)
                        if let branch = git.branchName {
                            Text(branch)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.system(size: 16))
                    .lineLimit(1)
                }

                // Directory line (show when no git info, or when dir differs from repo name)
                if let dir = info.directoryName, info.gitInfo == nil {
                    Text(dir)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                // Minimap (always shown)
                MinimapView(
                    minimap: info.minimap,
                    tabColor: accentColor,
                    isActiveTab: isActive,
                    jumpLabels: jumpLabels,
                    surfaceDirectories: tab.surfaceDirectories,
                    repoColorOverrides: repoColorOverrides,
                    onPaneTap: onPaneTap
                )
                .padding(.top, 2)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 10)

            Spacer(minLength: 0)
        }
        .opacity(isActive ? 1.0 : 0.9)
        .background(isActive ? activeBackground.padding(.trailing, -24) : nil)
        .overlay {
            if isActive {
                // Extend borders past the row's right edge to meet the
                // window divider line, using negative trailing padding
                VStack {
                    Rectangle().fill(accentColor).frame(height: 4)
                    Spacer()
                    Rectangle().fill(accentColor).frame(height: 4)
                }
                .padding(.trailing, -24)
            }
        }
    }

    private var tabColor: Color {
        tab.effectiveColor(overrides: repoColorOverrides).swiftUIColor
    }

    private var accentColor: Color { tabColor }

    private var colorBarColor: Color {
        isActive ? tabColor : .gray.opacity(0.3)
    }

    private var activeBackground: Color {
        tabColor.opacity(0.15)
    }
}

extension TabColor {
    /// Tab palette order: maps each case to a position in the 14-color
    /// ANSI palette extracted from the Ghostty config.
    static let orderedCases: [TabColor] = [
        .blue, .red, .green, .yellow, .magenta, .cyan, .neutral,
        .brightBlue, .brightRed, .brightGreen, .brightYellow,
        .brightMagenta, .brightCyan, .neutralBright
    ]

    /// Color from the user's Ghostty theme palette, with Catppuccin fallback.
    var swiftUIColor: Color {
        if self == .gray { return .gray }
        if let idx = Self.orderedCases.firstIndex(of: self),
           let appDel = Self.resolveAppDelegate(),
           idx < appDel.tabPalette.count {
            return Color(nsColor: appDel.tabPalette[idx])
        }
        return catppuccinFallback
    }

    /// Find AppDelegate through SwiftUI's delegate adaptor wrapper.
    private static func resolveAppDelegate() -> AppDelegate? {
        guard let delegate = NSApp?.delegate else { return nil }
        if let appDel = delegate as? AppDelegate { return appDel }
        // @NSApplicationDelegateAdaptor wraps the real delegate
        for child in Mirror(reflecting: delegate).children {
            if let appDel = child.value as? AppDelegate { return appDel }
        }
        return nil
    }

    /// Catppuccin Mocha fallback for when the Ghostty palette isn't available
    /// (tests, or before config loads).
    private var catppuccinFallback: Color {
        let hex = catppuccinHex
        return Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    // Catppuccin Mocha ANSI colors in palette order
    private var catppuccinHex: UInt {
        switch self {
        case .blue:           return 0x89B4FA  // ANSI 4
        case .red:            return 0xF38BA8  // ANSI 1
        case .green:          return 0xA6E3A1  // ANSI 2
        case .yellow:         return 0xF9E2AF  // ANSI 3
        case .magenta:        return 0xCBA6F7  // ANSI 5
        case .cyan:           return 0x94E2D5  // ANSI 6
        case .neutral:        return 0xBAC2DE  // ANSI 7 (white)
        case .brightBlue:     return 0x89DCEB  // ANSI 12
        case .brightRed:      return 0xEBA0AC  // ANSI 9
        case .brightGreen:    return 0xA6E3A1  // ANSI 10
        case .brightYellow:   return 0xF9E2AF  // ANSI 11
        case .brightMagenta:  return 0xF5C2E7  // ANSI 13
        case .brightCyan:     return 0x94E2D5  // ANSI 14
        case .neutralBright:  return 0xA6ADC8  // ANSI 15 (bright white)
        case .gray:           return 0x8E8E93
        }
    }
}
