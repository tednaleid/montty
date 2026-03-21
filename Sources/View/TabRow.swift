import SwiftUI

struct TabRow: View {
    let tab: Tab
    let isActive: Bool

    @State private var isEditing = false
    @State private var editName = ""

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
                        isEditing = false
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .bold))
                } else {
                    Text(tab.displayName.isEmpty ? "Terminal" : tab.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if let dir = directoryLabel {
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
            editName = tab.name
            isEditing = true
        }
    }

    private var directoryLabel: String? {
        guard let pwd = tab.workingDirectory, !pwd.isEmpty else { return nil }
        return (pwd as NSString).lastPathComponent
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
