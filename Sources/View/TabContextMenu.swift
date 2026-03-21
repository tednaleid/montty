import SwiftUI

struct TabContextMenu: View {
    let tab: Tab
    let onRename: () -> Void
    let onSetColor: (TabColor) -> Void
    let onClose: () -> Void

    var body: some View {
        Button("Rename...") { onRename() }

        Menu("Color") {
            TabColorPicker(currentColor: tab.color, onSelect: onSetColor)
        }

        Divider()

        Button("Close Tab") { onClose() }
    }
}
