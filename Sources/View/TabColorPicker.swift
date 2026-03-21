import SwiftUI

struct TabColorPicker: View {
    let currentColor: TabColor
    let onSelect: (TabColor) -> Void

    var body: some View {
        ForEach(TabColor.PresetColor.allCases, id: \.self) { preset in
            Button {
                onSelect(.preset(preset))
            } label: {
                HStack {
                    Circle()
                        .fill(preset.swiftUIColor)
                        .frame(width: 12, height: 12)
                    Text(preset.rawValue.capitalized)
                }
            }
        }

        Divider()

        Button {
            onSelect(.auto)
        } label: {
            HStack {
                Circle()
                    .strokeBorder(Color.secondary, lineWidth: 1)
                    .frame(width: 12, height: 12)
                Text("Auto")
            }
        }
    }
}
