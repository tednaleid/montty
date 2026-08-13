// ABOUTME: Reports the session snapshot montty would write right now, so
// ABOUTME: "did we build the right snapshot" can be checked without quitting.
#if DEBUG
import Foundation
import Network

extension DebugServer {
    /// The snapshot montty would write right now. Answers "what would we save"
    /// without quitting the app to find out.
    static func handleSession(connection: NWConnection) {
        DispatchQueue.main.async {
            guard let appDelegate = AppDelegate.shared() else {
                sendJSON(["error": "no app delegate"], status: 500, connection: connection)
                return
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(appDelegate.createSnapshot()) else {
                sendJSON(["error": "could not encode snapshot"], status: 500, connection: connection)
                return
            }
            sendRaw(data: data, contentType: "application/json", connection: connection)
        }
    }
}
#endif
