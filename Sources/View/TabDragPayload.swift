// ABOUTME: What a dragged sidebar tab carries: its id, under a type only montty declares,
// ABOUTME: so no other app accepts the drag and a release over empty space is a tear-off.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist. A tab dragged as plain text would paste its id
    /// into any editor it was dropped on.
    static let monttyTab = UTType(exportedAs: "com.montty.app.tab")
}

enum TabDragPayload {
    /// What a dragging session of `tabID` puts on the pasteboard.
    static func pasteboardItem(for tabID: UUID) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setData(
            Data(tabID.uuidString.utf8),
            forType: NSPasteboard.PasteboardType(UTType.monttyTab.identifier)
        )
        return item
    }

    /// The tab id a dropped provider carries, or nil when it carries none.
    /// `completion` runs on the main queue.
    static func tabID(from provider: NSItemProvider, completion: @escaping (UUID?) -> Void) {
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.monttyTab.identifier) { data, _ in
            let id = data.flatMap { String(data: $0, encoding: .utf8) }.flatMap(UUID.init(uuidString:))
            DispatchQueue.main.async { completion(id) }
        }
    }
}
