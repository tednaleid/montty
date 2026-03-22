import SwiftUI

struct TabRow: View {
    let tab: Tab
    let isActive: Bool
    @Binding var editingTabID: UUID?

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
                    .font(.system(size: 14, weight: .bold))
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
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.tail)
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
                    .font(.system(size: 11))
                    .lineLimit(1)
                }

                // Directory line (show when no git info, or when dir differs from repo name)
                if let dir = info.directoryName, info.gitInfo == nil {
                    Text(dir)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                // Minimap (always shown)
                MinimapView(
                    minimap: info.minimap,
                    tabColor: accentColor,
                    isActiveTab: isActive
                )
                .padding(.top, 2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Spacer(minLength: 0)
        }
        .background(isActive ? activeBackground : Color.clear)
        .onTapGesture(count: 2) {
            editingTabID = tab.id
        }
    }

    private var accentColor: Color {
        switch tab.color {
        case .preset(let preset):
            return preset.swiftUIColor
        case .auto:
            return .accentColor
        }
    }

    private var colorBarColor: Color {
        switch tab.color {
        case .preset(let preset):
            return preset.swiftUIColor
        case .auto:
            return isActive ? .accentColor : .gray.opacity(0.3)
        }
    }

    private var activeBackground: Color {
        switch tab.color {
        case .preset(let preset):
            return preset.swiftUIColor.opacity(0.15)
        case .auto:
            return Color.accentColor.opacity(0.1)
        }
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
}
