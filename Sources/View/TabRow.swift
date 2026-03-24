import SwiftUI

struct TabRow: View {
    let tab: Tab
    let isActive: Bool
    let activeTabColor: Color
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

    private var isAutoColor: Bool {
        if case .auto = tab.color { return true }
        return false
    }

    private var accentColor: Color {
        let preset = tab.effectivePresetColor
        return isAutoColor ? preset.desaturatedColor : preset.swiftUIColor
    }

    private var colorBarColor: Color {
        let preset = tab.effectivePresetColor
        if isAutoColor {
            return isActive ? preset.desaturatedColor : .gray.opacity(0.3)
        }
        return preset.swiftUIColor
    }

    private var activeBackground: Color {
        tab.effectivePresetColor.swiftUIColor.opacity(isAutoColor ? 0.07 : 0.15)
    }
}

extension TabColor.PresetColor {
    var swiftUIColor: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        case .gray: return .gray
        }
    }

    /// Desaturated variant for auto-derived tab colors.
    var desaturatedColor: Color {
        swiftUIColor.opacity(0.55)
    }
}
