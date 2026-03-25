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
    /// Catppuccin-themed color that adapts to dark (Mocha) / light (Latte) mode.
    var swiftUIColor: Color {
        if self == .gray { return .gray }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? self.darkHex : self.lightHex
            return NSColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1.0
            )
        })
    }

    // Catppuccin Mocha palette
    private var darkHex: UInt {
        switch self {
        case .rosewater: return 0xF5E0DC
        case .flamingo:  return 0xF2CDCD
        case .pink:      return 0xF5C2E7
        case .mauve:     return 0xCBA6F7
        case .red:       return 0xF38BA8
        case .maroon:    return 0xEBA0AC
        case .peach:     return 0xFAB387
        case .yellow:    return 0xF9E2AF
        case .green:     return 0xA6E3A1
        case .teal:      return 0x94E2D5
        case .sky:       return 0x89DCEB
        case .sapphire:  return 0x74C7EC
        case .blue:      return 0x89B4FA
        case .lavender:  return 0xB4BEFE
        case .gray:      return 0x8E8E93
        }
    }

    // Catppuccin Latte palette
    private var lightHex: UInt {
        switch self {
        case .rosewater: return 0xDC8A78
        case .flamingo:  return 0xDD7878
        case .pink:      return 0xEA76CB
        case .mauve:     return 0x8839EF
        case .red:       return 0xD20F39
        case .maroon:    return 0xE64553
        case .peach:     return 0xFE640B
        case .yellow:    return 0xDF8E1D
        case .green:     return 0x40A02B
        case .teal:      return 0x179299
        case .sky:       return 0x04A5E5
        case .sapphire:  return 0x209FB5
        case .blue:      return 0x1E66F5
        case .lavender:  return 0x7287FD
        case .gray:      return 0x8E8E93
        }
    }
}
