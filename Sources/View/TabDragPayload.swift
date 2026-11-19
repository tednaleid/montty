// ABOUTME: What a dragged sidebar tab carries: its id, under a type only this process can see,
// ABOUTME: so no other app accepts the drag and a release over empty space is a tear-off.

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist. A tab dragged as plain text would paste its id
    /// into any editor it was dropped on.
    static let monttyTab = UTType(exportedAs: "com.montty.app.tab")
}

enum TabDragPayload {
    /// A provider for dragging `tabID`, visible to no other process.
    static func provider(for tabID: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.monttyTab.identifier, visibility: .ownProcess
        ) { completion in
            completion(Data(tabID.uuidString.utf8), nil)
            return nil
        }
        return provider
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
