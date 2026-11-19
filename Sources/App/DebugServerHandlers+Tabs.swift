// ABOUTME: Moves a tab to a window through the same path a sidebar drop takes,
// ABOUTME: so a cross-window move can be checked without synthesizing a drag.
#if DEBUG
import Foundation
import Network

extension DebugServer {
    /// `POST /move-tab?tab=<uuid>&window=<uuid>&index=<n>`. `index` defaults to
    /// the end of the window's tab list. Everything past parsing is
    /// `AppDelegate.moveTab`, which is what the sidebar's drop handler calls.
    static func handleMoveTab(query: [String: String], connection: NWConnection) {
        DispatchQueue.main.async {
            guard let appDelegate = AppDelegate.shared() else {
                sendJSON(["error": "no app delegate"], status: 500, connection: connection)
                return
            }
            guard let tabID = query["tab"].flatMap(UUID.init(uuidString:)),
                  let windowID = query["window"].flatMap(UUID.init(uuidString:)),
                  let window = appDelegate.registry.window(id: windowID) else {
                sendJSON(["error": "need tab=<uuid> and window=<uuid> naming an open window"],
                         status: 400, connection: connection)
                return
            }
            let index = query["index"].flatMap(Int.init) ?? window.tabStore.tabs.count
            guard appDelegate.moveTab(id: tabID, to: window, at: index) else {
                sendJSON(["error": "no such tab"], status: 404, connection: connection)
                return
            }
            sendJSON(["ok": true], connection: connection)
        }
    }
}
#endif
