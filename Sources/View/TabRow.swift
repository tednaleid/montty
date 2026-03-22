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

    var body: some View {
        HStack(spacing: 0) {
            // Color indicator bar
            Rectangle()
                .fill(colorBarColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("Tab name", text: $editName, onCommit: {
                        tab.name = editName
                        editingTabID = nil
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .bold))
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
                    Text(tab.tabInfo.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if let dir = tab.tabInfo.directoryName {
                    Text(dir)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Spacer()
        }
        .background(isActive ? activeBackground : Color.clear)
        .onTapGesture(count: 2) {
            editingTabID = tab.id
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
