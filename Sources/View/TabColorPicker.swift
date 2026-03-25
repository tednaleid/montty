import SwiftUI

struct TabColorPicker: View {
    let currentColor: TabColor
    /// Called with a color to set an override, or nil to clear the override.
    let onSelect: (TabColor?) -> Void

    var body: some View {
        ForEach(TabColor.allCases.filter { $0 != .gray }, id: \.self) { color in
            Button {
                onSelect(color)
            } label: {
                HStack {
                    Circle()
                        .fill(color.swiftUIColor)
                        .frame(width: 12, height: 12)
                    Text(color.rawValue.capitalized)
                    if color == currentColor {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }
        }

        Divider()

        Button {
            onSelect(nil)
        } label: {
            HStack {
                Circle()
                    .strokeBorder(Color.secondary, lineWidth: 1)
                    .frame(width: 12, height: 12)
                Text("Reset")
            }
        }
    }
}
